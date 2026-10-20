# TidyShot Phase 3.1: Feedback After the Phase 3 Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the menu bar item from SwiftUI to AppKit so Recent Captures becomes a hover submenu of thumbnail rows (copy URL, copy image, delete) with a full-size preview beside it, replacing the gallery window; add a signed GET so Copy Image works for upload-only captures; cut the delete confirmation to Delete and Cancel, with a "remove from history anyway" alert only after a failed storage DELETE; remove the app-name token from both naming templates and migrate stored templates; give the Upload tab neutral "Required" prompts with example captions; and draw the selection crosshair black or white depending on the screen under it.

**Architecture:** `StatusMenuController` owns an `NSStatusItem` whose `NSMenu` is rebuilt in `menuNeedsUpdate(_:)`; the SwiftUI app keeps only its `Settings` scene, which AppKit opens through `SettingsOpener` (SwiftUI's `openSettings` action, read by a zero-size `NSHostingView` in the status item's button). `RecentCapturesMenu` fills the submenu with `RecentCaptureMenuItemView`s, AppKit views that host the SwiftUI `RecentCaptureRow` and carry tracking areas for the row highlight and the thumbnail hover; row actions close the menu and run once tracking has ended, and the hover shows a non-activating `PreviewPanel` at `.popUpMenu` level, placed by the pure `PreviewPlacement`. Pure helpers carry the testable logic: `TemplateMigration` (the removed token), `CaptureDeletion` (the alert texts), `RecentCaptureFormatting` (row text and button states), `Luminance` and `CrosshairStyle` (the crosshair colour), `ImageEncoder.decode` (PNG and its scale) and `S3Destination.download` (the signed GET).

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation, AppKit (`NSStatusItem`, `NSMenu` with custom item views, `NSMenuDelegate`, `NSTrackingArea`, `NSPanel`, `NSAlert`, `RunLoop.perform(inModes:)`), SwiftUI (`NSHostingView`, `@Environment(\.openSettings)`, `Settings` scene), Observation (`withObservationTracking`), CoreGraphics (`CGImage.cropping`, bitmap `CGContext`), ImageIO, `RelativeDateTimeFormatter`, Swift Testing, XcodeGen 2.46.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`, sections 2.5 (all five paragraphs), 3, 5 and 6 (Phase 3.1).

Builds on Phase 3 (`docs/superpowers/plans/2026-10-19-phase-3-gallery-and-key-templates.md`). Work happens on the branch `phase-3-1-feedback`, which already holds Phase 3, the Phase 3.1 spec commit `238e1b4`, and this plan. Confirm:

```bash
git switch phase-3-1-feedback
git merge-base --is-ancestor 238e1b4 HEAD && echo SPEC_PRESENT
```
Expected: `Already on 'phase-3-1-feedback'` (or `Switched to branch 'phase-3-1-feedback'`) then `SPEC_PRESENT`.

## Global Constraints

- Every Phase 0, 1, 2 and 3 constraint still applies: minimum macOS `26.0`, Xcode 27.1 with the macOS 27.0 SDK, App Sandbox on with no new entitlements, Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `KeyboardShortcuts` as the only package, credentials only in the Keychain, files in the save folder only through the security-scoped bookmark, thumbnails and upload-only files in the container next to `history.json`, one token engine for file names and object keys, keys named when the upload starts, HEAD before PUT, and no GPL-licensed code read or copied.
- No `{app}` anywhere. The token, `TemplateContext.appName`, `FileNamer.name(appName:counter:)` (now `name(counter:)`) and the `appName` parameter of `AppCoordinator.save` are gone, and the captions list `{date} {year} {month} {day} {time} {datetime} {hostname} {counter} {random} {random:8}`. Stored templates (the file name template in `AppSettings`, the key template in `S3DestinationConfig`) go through `TemplateMigration.removingAppToken(from:fallback:)`: the token is deleted with the one separator (`-`, `_`, `.`, `/` or space) it would leave doubled or dangling, a blank result becomes the default template, and `AppSettings` writes the rewritten values back once. The only mentions left are `TemplateMigration`, its tests, the migration comments in `AppSettings` and `S3DestinationConfig`, and the migration item in the Phase 3.1 checklist. `CaptureRecord.appName` stays so history written before Phase 3.1 decodes unchanged; new records store nil.
- The delete path stays single: `AppCoordinator.deleteCapture(recordID:)`, guarded by `deletingIDs`, for the overlay and for Recent Captures. First alert: message `Delete this capture?`, informative text the one line from `CaptureDeletion.confirmationText(for:)` (`Removes it from object storage and from history.` whenever the object can be deleted), buttons Delete (destructive) and Cancel. Only when the storage `DELETE` fails or no credentials are stored: message `Couldn't delete it from storage: <reason>`, informative text `Remove it from history anyway? The object stays in the bucket.`, buttons Remove (destructive) and Cancel; Remove drops the record, its thumbnail and a temporary file in `pending`, never the object or a file in the save folder. Nothing offers "Remove from History Only" any more.
- The menu must not activate the app except for alerts and Settings (and the Phase 0 permission window). Menu item actions, row clicks, the copy buttons and the preview panel never call `activate`; `NSAlert` paths and `SettingsOpener.open()` do.
- No work in SwiftUI `body`. `RecentCaptureRow` gets its strings and flags precomputed by `RecentCaptureFormatting`, loads its thumbnail in `.task`, and the preview loads in a `Task` through `ThumbnailProvider`, whose file reads run detached. `SelectionView` samples luminance in its mouse handlers and when the snapshot arrives, never while drawing.
- Menu bar: `NSStatusItem` plus `NSMenu`, rebuilt each time it opens; the icon is `camera.viewfinder`, `arrow.up.circle` while `AppCoordinator.isUploading`. Shortcuts appear in the capture items' titles (`Capture Area  ⌃⇧4`), never as key equivalents. The SwiftUI app declares only `Settings { SettingsView() }`.
- Recent Captures: the newest 15 records; row actions close the whole menu with `cancelTracking()` and run after tracking ends (`RunLoop.main.perform(inModes: [.default])`), so no alert opens inside menu tracking. The preview panel is non-activating, at `.popUpMenu` level, not an `isFloatingPanel`, ignores the mouse, and hides on hover exit, on any row action and in `menuDidClose(_:)`.
- Copy Image reads the local file first and otherwise downloads with `S3Destination.download(key:)` (signed GET at the record's `objectLocation`, never the public URL). "Copying image…" (only when downloading) and "Image copied" follow the Show notification setting; "Could not copy image" is always posted.
- Crosshair: the mean luminance of a 24 by 24 point square around the cursor; above 0.5 black at 0.8 alpha, otherwise white at 0.8 alpha; before the snapshot arrives white with a one-pixel black edge beneath. The drag rectangle border and the completed rectangle border use the same colour.
- Tests use Swift Testing, run with `xcodebuild test`. Baseline `Test run with 161 tests in 24 suites passed`; the totals after each task are in the table below, and the plan ends at `186 tests in 28 suites`.
- Commit after every task with a conventional commit message. Never include a Claude Code session URL in a commit or PR. This plan never pushes or opens a PR: Task 9 stops after its commit, and the controller pushes and opens the PR after the whole-branch review.

## Test totals

| After | Added | Removed or replaced | Total |
|---|---|---|---|
| Baseline | | | 161 tests in 24 suites |
| Task 1 | `TemplateMigrationTests` (new suite, 4), `TemplateExpanderTests.appIsNotAToken`, `AppSettingsTests.storedTemplatesLoseTheRemovedAppToken`, `S3DestinationConfigTests.storedKeyTemplateLosesTheRemovedAppToken`; replacements `hostnameCounterAndRandom`, `datetimeToken`, `removedAppTokenIsLiteralText` | `TemplateExpanderTests.appHostnameCounterAndRandom`, `FileNamerTests.appAndDatetimeTokens`, `FileNamerTests.missingAppFallsBackToScreen` | 168 tests in 25 suites |
| Task 2 | `ConnectionTesterTests.readableSummaryDoesNotEchoTheProbeURL` | | 169 in 25 |
| Task 3 | `CaptureDeletionTests.confirmationTextIsOneLine`, `alertTexts`, and `confirmationTextSaysWhenTheObjectStays` rewritten | `CaptureDeletionTests.confirmationTextNamesWhatIsRemoved`, the Phase 3 `confirmationTextSaysWhenTheObjectStays` | 170 in 25 |
| Task 4 | `S3DestinationTests.downloadIsASignedGetThatReturnsTheBody`, `downloadThrowsTheSummarisedErrorOnFailure`, `ImageEncoderTests.decodeReadsBackTheScale` | | 173 in 25 |
| Task 5 | `LuminanceTests` (new suite, 6) | | 179 in 26 |
| Task 6 | | | 179 in 26 |
| Task 7 | `RecentCaptureFormattingTests` (new suite, 3) | (`ThumbnailProviderTests` keeps its 5 tests) | 182 in 27 |
| Task 8 | `PreviewPlacementTests` (new suite, 4) | (the conditional fallback in Step 8 removes this suite: 182 in 27) | 186 in 28 |
| Task 9 | | | 186 in 28 |

## Build and test commands used throughout

```bash
# regenerate the project after any project.yml change or after adding, moving or deleting files
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
# launch the built app (quit any other TidyShot first, or two menu bar items appear)
open .build/Build/Products/Debug/TidyShot.app
```

XcodeGen only sees files that exist when it runs. Every task that creates, moves or deletes a Swift file runs `xcodegen generate` before building; a "cannot find 'X' in scope" error for a type you just wrote means the project was not regenerated. The test output always contains two `History file could not be read or decoded` log lines (from the corrupt-file tests) and some `com.apple.linkd.autoShortcut` lines that contain `error: Error Domain=NSCocoaErrorDomain Code=4097`; neither is a failure. A real problem shows as a compiler `error:` with a file and line, a `warning:` in a `TidyShot/` file, or a `✘` line.

Code signing note: this Mac has ad-hoc signing (`CODE_SIGN_IDENTITY = -`), so Screen Recording must be re-granted after each rebuild and the keychain may ask "TidyShot wants to use your confidential information" once per build (click Always Allow). A rebuilt app shares the container of the previous build, so `history.json`, `thumbnails/`, `pending/` and the preferences carry over, which is what the template migration check in the Phase 3.1 checklist relies on.

## File structure

```
TidyShot/
  App/
    TidyShotApp.swift                        replaced (Task 6): only the Settings scene
    AppDelegate.swift                        modified (Task 6): creates the StatusMenuController
    StatusMenuController.swift               new (Task 6), modified (Tasks 7, 8): NSStatusItem, NSMenu, icon, Settings…
    SettingsOpener.swift                     new (Task 6): opens the SwiftUI Settings scene from AppKit
    MenuContent.swift                        deleted (Task 6)
    AppCoordinator.swift                     modified (Tasks 1, 3, 4, 7): no app name, two delete alerts, copyImage, copyLink, no gallery
  RecentCaptures/                            new folder (Task 7); replaces Gallery/
    ThumbnailProvider.swift                  moved from Gallery/ (Task 7), comment only
    RecentCaptureFormatting.swift            new (Task 7): row name, relative time, button states (pure)
    RecentCaptureRow.swift                   new (Task 7): RecentCaptureActions, RecentCaptureRowState, the SwiftUI row
    RecentCaptureMenuItemView.swift          new (Task 7), replaced (Task 8): hosting view plus tracking areas
    RecentCapturesMenu.swift                 new (Task 7), replaced (Task 8): the submenu, row actions, preview
    PreviewPlacement.swift                   new (Task 8): where the preview goes (pure)
    PreviewPanel.swift                       new (Task 8): the floating preview
  Gallery/                                   deleted (Task 7): GalleryModel, GalleryView, GalleryWindowController
  History/
    CaptureDeletion.swift                    replaced (Task 3): alert texts
    CaptureRecord.swift                      comment only (Task 7)
  Output/
    TemplateMigration.swift                  new (Task 1): drops the removed token from stored templates
    TemplateExpander.swift                   modified (Task 1): no app token, TemplateContext without appName
    FileNamer.swift                          modified (Task 1): name(counter:)
    ImageEncoder.swift                       modified (Task 4): decode(_:)
    Notifier.swift                           modified (Task 4): notify(title:body:)
    ThumbnailMaker.swift, SaveLocation.swift comments only (Task 7)
  Selection/
    Luminance.swift                          new (Task 5): Luminance, CrosshairStyle
    SelectionView.swift                      modified (Task 5): crosshair and borders in the sampled colour
  Settings/
    AppSettings.swift                        modified (Task 1): migrates the file name template and the stored config
    UploadSettingsView.swift                 modified (Tasks 1, 2): example key context, Required prompts and captions
    SettingsView.swift                       modified only if the Upload tab scrolls (Task 2 Step 6): 600 by 840
  Upload/
    S3Destination.swift                      modified (Task 4): download(key:)
    S3DestinationConfig.swift                modified (Task 1): migrates the key template on decode
    ConnectionTester.swift                   modified (Tasks 1, 2): no app name, summary without the URL
    Destination.swift                        comment only (Task 1)
TidyShotTests/
  TemplateMigrationTests.swift               new (Task 1)
  TemplateExpanderTests.swift                replaced (Task 1)
  FileNamerTests.swift                       replaced (Task 1)
  ObjectKeyNamerTests.swift, UploadQueueTests.swift, AppSettingsTests.swift, S3DestinationConfigTests.swift   modified (Task 1)
  ConnectionTesterTests.swift                modified (Task 2)
  CaptureDeletionTests.swift                 replaced (Task 3)
  S3DestinationTests.swift, ImageEncoderTests.swift   modified (Task 4)
  LuminanceTests.swift                       new (Task 5)
  RecentCaptureFormattingTests.swift         new (Task 7)
  PreviewPlacementTests.swift                new (Task 8)
docs/testing/phase-3-1-manual-checklist.md   new (Task 9)
docs/testing/phase-1-manual-checklist.md, phase-3-manual-checklist.md   modified (Tasks 1, 9)
README.md                                    modified (Tasks 1, 9)
```

## Design decisions made while planning

- **Opening Settings from AppKit:** a scratch app on this machine (macOS 27, SDK 27.0, only a `Settings` scene, `LSUIElement`) showed that `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` returns `true` and opens nothing. SwiftUI's `OpenSettingsAction` (`@Environment(\.openSettings)`, macOS 14+) does open it, also a second time after the window was closed, when read by a view in a zero-size `NSHostingView` added to the status item's button (always on screen, so `onAppear` runs at launch) and called later from AppKit. `SettingsOpener` packages that; a hidden `MenuBarExtra` is not needed. The app is activated first so the window comes to the front.
- **Rows in a tracking menu:** checked with the same scratch app and again in the test host with the plan's own `RecentCaptureMenuItemView`, `PreviewPanel` and `PreviewPlacement`. A tracking area on the view set as `NSMenuItem.view` gets `mouseEntered` and `mouseExited` while the menu tracks (AppKit follows the real cursor position, so this is checked by moving the mouse); clicks in the item's `NSHostingView` reach a plain-style SwiftUI `Button` covering the left of the row and the borderless icon buttons beside it, each firing only its own action; a `.popUpMenu`-level non-activating panel ordered front during tracking is the frontmost on-screen window, above the menu; `menuDidClose(_:)` fires on `cancelTracking()`; and a block given to `RunLoop.main.perform(inModes: [.default])` from inside the menu runs only after tracking has ended. Setting `isFloatingPanel = true` on the panel moved its level back to `.floating`, under the menu, so `PreviewPanel` does not. Task 8 Step 8 keeps the in-row fallback (an enlarged thumbnail inside the hovered row) as a conditional step for a macOS that stops showing the panel; it was compiled and its test total (182 in 27) checked, but it is not part of the verified final state.
- **Row layout:** 360 by 52 points; the thumbnail is 56 points wide (56 by 42, the 4:3 box fits most captures without making 15 rows taller than a laptop screen); the plain button covering thumbnail, name and time copies the URL or the file, and three 24-point borderless buttons follow. The highlight is drawn by the row from an `@Observable` state that the AppKit tracking area sets, because a menu does not highlight custom item views.
- **Rebuilt on open, not live:** `menuNeedsUpdate(_:)` rebuilds the status menu and the 15 rows each time the menu opens. Rows show their records as they were then; an upload finishing while the menu is open shows on the next open. The "Recent Captures" item and its submenu are created once and re-added, because an `NSMenu` can be the submenu of only one item.
- **Actions after tracking:** row buttons call `cancelTracking()` on the status menu and run their work with `RunLoop.main.perform(inModes: [.default])`. The default mode is not entered until tracking ends, so the delete confirmation's `runModal()` never nests inside the menu's tracking loop, and Copy Image's notification is posted after the menu has gone.
- **Shortcut display:** the capture items keep the shortcut in their title (as the SwiftUI menu did). `NSMenuItem.setShortcut(for:)` from `KeyboardShortcuts` would show it right-aligned, but as a key equivalent it fires the capture while the menu is open and the buffered global hotkey fires it again when the menu closes.
- **Delete texts:** the first alert's line is exactly `Removes it from object storage and from history.` whenever there is an object to delete (uploaded with a known location, a reserved key from a cancelled upload, or an upload in flight). Without one it says what does disappear: `Removes it from your save folder and from history.` for a saved file, `Removes it from history.` otherwise, and a record uploaded before Phase 3 (no `objectLocation`) adds `The uploaded object stays in the bucket.` Delete still removes the local file and the thumbnail, as in Phase 3. Missing credentials count as a storage failure (reason `No credentials are saved in Settings > Upload.`), so that record is not stuck either.
- **Copy Image source:** the local file when it can be read (save folder through the bookmark, `pending` directly), otherwise the object by signed GET from where the record says it went, with the credentials stored now. A record uploaded before Phase 3 has no location, so without its local file the button is disabled. The PNG's DPI gives the paste scale (`ImageEncoder.decode`), so Retina captures paste at point size.
- **App name on records:** removing the token leaves nothing that needs the capturing app, so `save(_:)` no longer reads it and new records store `appName: nil`. The field stays because Phase 1 to 3 history files carry it, and a Recent Captures row with neither URL nor file falls back to it for its name.
- **Luminance API:** `Luminance.mean(of:in:)` returns `Double?`, nil when the rect lies wholly outside the image (cursor off the snapshot), which `CrosshairStyle(luminance:)` turns into the outlined style. The crop is drawn into an 8-bit RGBA buffer of at most 32 by 32 pixels, so a 2x display's 48 by 48 pixel sample is averaged by the downscale and the cost does not grow with the scale.

---

### Task 1: Remove the `{app}` token and migrate stored templates (TDD)

**Files:**
- Create: `TidyShot/Output/TemplateMigration.swift`
- Create: `TidyShotTests/TemplateMigrationTests.swift`
- Modify: `TidyShot/Output/TemplateExpander.swift` (edits below)
- Modify: `TidyShot/Output/FileNamer.swift` (one edit)
- Modify: `TidyShot/Settings/AppSettings.swift` (two edits)
- Modify: `TidyShot/Upload/S3DestinationConfig.swift` (one edit)
- Modify: `TidyShot/Upload/Destination.swift` (one comment)
- Modify: `TidyShot/Upload/ConnectionTester.swift` (one edit)
- Modify: `TidyShot/Settings/UploadSettingsView.swift` (one edit)
- Modify: `TidyShot/App/AppCoordinator.swift` (edits below)
- Modify: `TidyShotTests/TemplateExpanderTests.swift` (full replacement), `TidyShotTests/FileNamerTests.swift` (full replacement), `TidyShotTests/ObjectKeyNamerTests.swift`, `TidyShotTests/UploadQueueTests.swift`, `TidyShotTests/AppSettingsTests.swift`, `TidyShotTests/S3DestinationConfigTests.swift` (edits below)
- Modify: `README.md`, `docs/testing/phase-1-manual-checklist.md`, `docs/testing/phase-3-manual-checklist.md` (edits below)

**Interfaces:**
- Consumes: `TemplateExpander`, `TemplateContext`, `FileNamer`, `ObjectKeyNamer.defaultTemplate`, `FileNamer.defaultTemplate` (Phase 3).
- Produces:
  - `nonisolated enum TemplateMigration { static let removedAppToken: String; static let separators: Set<Character>; static func removingAppToken(from template: String, fallback: String) -> String }`.
  - `TemplateContext` loses `appName`: `init(date: Date = Date(), counter: Int = 0, hostname: String = HostName.local())`.
  - `TemplateExpander.Token` loses `.app`; `TemplateExpander.tokenList` is `{date} {year} {month} {day} {time} {datetime} {hostname} {counter} {random} {random:8}`.
  - `FileNamer.name(counter: Int) -> String` replaces `name(appName:counter:)`.
  - `AppCoordinator.save(_ result: CaptureResult) async` replaces `save(_:appName:)`. New records store `appName: nil`; `CaptureRecord.appName` stays so older history files keep theirs.
  - `AppSettings.init(defaults:)` and `S3DestinationConfig.init(from:)` run stored templates through `TemplateMigration`; `AppSettings` writes the rewritten values back once.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/TemplateMigrationTests.swift`:
```swift
import Testing
@testable import TidyShot

struct TemplateMigrationTests {
    func migrate(_ template: String) -> String {
        TemplateMigration.removingAppToken(from: template, fallback: "FALLBACK")
    }

    @Test func templatesWithoutTheTokenAreUnchanged() {
        #expect(migrate("{random:6}") == "{random:6}")
        #expect(migrate("Screenshot {date} at {time}") == "Screenshot {date} at {time}")
        #expect(migrate("a--b  {date}") == "a--b  {date}")
        #expect(migrate("{application}") == "{application}")
    }

    @Test func tokenBetweenSeparatorsTakesOneOfThemWithIt() {
        #expect(migrate("shots/{app}/{random:8}") == "shots/{random:8}")
        #expect(migrate("shots/{app}-{random}") == "shots/{random}")
        #expect(migrate("Screenshot {app} {datetime}") == "Screenshot {datetime}")
        #expect(migrate("{date}_{app}.{counter}") == "{date}_{counter}")
    }

    @Test func tokenAtEitherEndTakesItsSeparatorWithIt() {
        #expect(migrate("{app} {datetime}") == "{datetime}")
        #expect(migrate("{app}/{date}/{random}") == "{date}/{random}")
        #expect(migrate("Screenshot {date} {app}") == "Screenshot {date}")
        #expect(migrate("{random}-{app}") == "{random}")
    }

    @Test func tokenNextToTextIsDroppedAndAnEmptyResultFallsBack() {
        #expect(migrate("x{app}y") == "xy")
        #expect(migrate("{app}{app}-{random}") == "{random}")
        #expect(migrate("{app}") == "FALLBACK")
        #expect(migrate(" {app} ") == "FALLBACK")
    }
}
```

The `{app}` examples in the expander tests move to `{hostname}`, and one test checks that `{app}` is no longer a token. Replace the whole file:

`TidyShotTests/TemplateExpanderTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct TemplateExpanderTests {
    /// 2026-10-19 11:56:03 in the current time zone, matching what DateFormatter will print.
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!
    let expander = TemplateExpander(randomString: { String(repeating: "X", count: $0) })

    func context(counter: Int = 7, hostname: String = "miffle") -> TemplateContext {
        TemplateContext(date: fixedDate, counter: counter, hostname: hostname)
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

    /// Removed in Phase 3.1: `{app}` is literal text now, and the captions no longer list it.
    @Test func appIsNotAToken() {
        #expect(TemplateExpander.Token(name: "app") == nil)
        #expect(TemplateExpander.parse("{app}-{date}") == [.literal("{app}-"), .token(.date)])
        #expect(!TemplateExpander.tokenList.contains("{app}"))
    }

    @Test func randomLengthDefaultsAndClamps() {
        #expect(TemplateExpander.parse("{random}") == [.token(.random(length: 6))])
        #expect(TemplateExpander.parse("{random:0}") == [.token(.random(length: 1))])
        #expect(TemplateExpander.parse("{random:999}") == [.token(.random(length: 64))])
        #expect(TemplateExpander.parse("{random:1000}") == [.token(.random(length: 64))])
        #expect(TemplateExpander.parse("{random:99999999999999999999999}") == [.token(.random(length: 64))])
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

    @Test func hostnameCounterAndRandom() {
        #expect(expander.expand("{hostname}/{counter}-{random:3}", context: context(), style: .objectKey)
                == "miffle/7-XXX")
    }

    @Test func objectKeyStyleSanitisesTokenValuesOnly() {
        let odd = context(hostname: "Tim's Mac (2)")
        #expect(expander.expand("{hostname}", context: odd, style: .fileName) == "Tim's Mac (2)")
        #expect(expander.expand("{hostname}", context: odd, style: .objectKey) == "Tim-s-Mac-2")
        // Literal text is the template author's business; the key namer validates it.
        #expect(expander.expand("a b/{counter}", context: odd, style: .objectKey) == "a b/7")
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
        #expect(TemplateExpander.normalizeHostname("build_host_01") == "build-host-01")
        #expect(TemplateExpander.normalizeHostname("-a__b--c..d.-e-") == "a-b-c.d.e")
        #expect(TemplateExpander.normalizeHostname("Café.local") == "caf")
        #expect(TemplateExpander.normalizeHostname("") == "mac")
        #expect(TemplateExpander.normalizeHostname(".local") == "mac")
        #expect(TemplateExpander.normalizeHostname("__") == "mac")
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

The file namer tests call `name(counter:)`, and their two `{app}` tests become a `{datetime}` test and a test that `{app}` is literal text now. Replace the whole file:

`TidyShotTests/FileNamerTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct FileNamerTests {
    /// 2026-10-19 11:56:03 in the current time zone, matching what DateFormatter will print.
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!

    func namer(_ template: String) -> FileNamer {
        FileNamer(template: template, now: { fixedDate }, randomString: { String(repeating: "X", count: $0) }, hostname: "miffle")
    }

    @Test func defaultTemplateMatchesSystemStyle() {
        let name = FileNamer(now: { fixedDate }).name(counter: 1)
        #expect(name == "Screenshot 2026-10-19 at 11.56.03")
    }

    @Test func datetimeToken() {
        #expect(namer("Shot {datetime}").name(counter: 1) == "Shot 2026-10-19 11.56.03")
    }

    /// `{app}` was removed in Phase 3.1; stored templates are migrated, so this only shows that the
    /// engine treats it like any other unknown text.
    @Test func removedAppTokenIsLiteralText() {
        #expect(namer("{app}").name(counter: 1) == "{app}")
    }

    @Test func counterToken() {
        #expect(namer("shot-{counter}").name(counter: 42) == "shot-42")
    }

    @Test func randomTokenDefaultsToSixCharacters() {
        #expect(namer("{random}").name(counter: 1) == "XXXXXX")
    }

    @Test func randomTokenWithLength() {
        #expect(namer("{random:8}-{random:2}").name(counter: 1) == "XXXXXXXX-XX")
    }

    @Test func yearMonthDayAndHostnameTokens() {
        #expect(namer("{year}/{month}/{day} {hostname}").name(counter: 1) == "2026-10-19 miffle")
    }

    @Test func sanitizeReplacesPathSeparatorsAndColons() {
        #expect(FileNamer.sanitize("a/b:c") == "a-b-c")
    }

    @Test func sanitizeTrimsWhitespaceAndLeadingDot() {
        #expect(FileNamer.sanitize("  .hidden ") == "_hidden")
    }

    @Test func emptyResultFallsBackToScreenshot() {
        #expect(namer("   ").name(counter: 1) == "Screenshot")
    }

    @Test func realRandomStringUsesAlphanumerics() {
        let value = FileNamer.randomString(length: 32)
        #expect(value.count == 32)
        #expect(value.allSatisfy { $0.isLetter || $0.isNumber })
        #expect(value.allSatisfy { $0.isASCII })
    }

    @Test func uniqueURLAppendsCounterWhenFileExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = FileNamer.uniqueURL(baseName: "Shot", ext: "png", in: dir)
        #expect(first.lastPathComponent == "Shot.png")
        try Data().write(to: first)

        let second = FileNamer.uniqueURL(baseName: "Shot", ext: "png", in: dir)
        #expect(second.lastPathComponent == "Shot 2.png")
        try Data().write(to: second)

        let third = FileNamer.uniqueURL(baseName: "Shot", ext: "png", in: dir)
        #expect(third.lastPathComponent == "Shot 3.png")
    }
}
```

In `TidyShotTests/ObjectKeyNamerTests.swift`:

Replace:
```swift
    func context(app: String? = "Safari", counter: Int = 7) -> TemplateContext {
        TemplateContext(date: fixedDate, appName: app, counter: counter, hostname: "miffle")
    }
```
with:
```swift
    func context(counter: Int = 7, hostname: String = "miffle") -> TemplateContext {
        TemplateContext(date: fixedDate, counter: counter, hostname: hostname)
    }
```

Replace:
```swift
        #expect(namer("{app}/{date}_{time}-{counter}").makeKey(ext: "png", context: context())
                == "Safari/2026-10-19_11-56-03-7.png")
```
with:
```swift
        #expect(namer("{hostname}/{date}_{time}-{counter}").makeKey(ext: "png", context: context())
                == "miffle/2026-10-19_11-56-03-7.png")
```

Replace:
```swift
        #expect(namer("{app}/{random:2}").makeKey(ext: "png", context: context(app: "Google Chrome (Beta)")) == "Google-Chrome-Beta/XX.png")
        #expect(namer("{app}").makeKey(ext: "png", context: context(app: nil)) == "Screen.png")
```
with:
```swift
        #expect(namer("{hostname}/{random:2}").makeKey(ext: "png", context: context(hostname: "Tim's Mac (2)")) == "Tim-s-Mac-2/XX.png")
        #expect(namer("{hostname}").makeKey(ext: "png", context: context(hostname: "")) == "x.png")
```

Replace:
```swift
        #expect(ObjectKeyNamer.validate("{foo}") == .unknownToken("foo"))
```
with:
```swift
        #expect(ObjectKeyNamer.validate("{foo}") == .unknownToken("foo"))
        #expect(ObjectKeyNamer.validate("{app}/{random}") == .unknownToken("app"))
```

In `TidyShotTests/UploadQueueTests.swift`:

Replace:
```swift
                                keyNamer: ObjectKeyNamer(template: "{app}/{date}/{counter}-{random:2}",
```
with:
```swift
                                keyNamer: ObjectKeyNamer(template: "{hostname}/{date}/{counter}-{random:2}",
```

Replace:
```swift
        let naming = TemplateContext(date: captured, appName: "Safari", counter: 3, hostname: "miffle")
```
with:
```swift
        let naming = TemplateContext(date: captured, counter: 3, hostname: "miffle")
```

Replace:
```swift
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/Safari/2026-10-19/3-KK.png")!,
                                                              key: "Safari/2026-10-19/3-KK.png")) }
```
with:
```swift
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/miffle/2026-10-19/3-KK.png")!,
                                                              key: "miffle/2026-10-19/3-KK.png")) }
```

In `TidyShotTests/AppSettingsTests.swift`:

Replace:
```swift
        second.s3Config = nil
        #expect(AppSettings(defaults: defaults).s3Config == nil)
    }
```
with:
```swift
        second.s3Config = nil
        #expect(AppSettings(defaults: defaults).s3Config == nil)
    }

    /// `{app}` was removed in Phase 3.1. Templates saved before that lose it on load, and the
    /// rewritten values are stored, so the next launch reads them as they are.
    @Test func storedTemplatesLoseTheRemovedAppToken() throws {
        let defaults = freshDefaults()
        defaults.set("{app} {datetime}", forKey: "fileNameTemplate")
        let old = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                      publicURLTemplate: "https://snap.tky.io/{key}", keyTemplate: "shots/{app}/{random:8}")
        defaults.set(try JSONEncoder().encode(old), forKey: "s3DestinationConfig")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.fileNameTemplate == "{datetime}")
        #expect(settings.s3Config?.keyTemplate == "shots/{random:8}")
        #expect(defaults.string(forKey: "fileNameTemplate") == "{datetime}")
        let stored = try #require(defaults.data(forKey: "s3DestinationConfig"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("{app}"))
    }
```

In `TidyShotTests/S3DestinationConfigTests.swift`:

Replace:
```swift
        #expect(try decode("{\(common),\"keyTemplate\":\"{date}/{random}\",\"keyPrefix\":\"ignored\"}").keyTemplate == "{date}/{random}")
    }
```
with:
```swift
        #expect(try decode("{\(common),\"keyTemplate\":\"{date}/{random}\",\"keyPrefix\":\"ignored\"}").keyTemplate == "{date}/{random}")
    }

    /// `{app}` was removed in Phase 3.1; a stored key template loses it when it is decoded.
    @Test func storedKeyTemplateLosesTheRemovedAppToken() throws {
        func roundTrip(_ template: String) throws -> S3DestinationConfig {
            var config = aws
            config.keyTemplate = template
            return try JSONDecoder().decode(S3DestinationConfig.self, from: JSONEncoder().encode(config))
        }
        #expect(try roundTrip("{app}/{date}/{random}").keyTemplate == "{date}/{random}")
        #expect(try roundTrip("{app}").keyTemplate == ObjectKeyNamer.defaultTemplate)
        #expect(try roundTrip("shots/{random}").keyTemplate == "shots/{random}")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:" | sort -u | head
```
Expected: compile errors, among them `cannot find 'TemplateMigration' in scope`.

- [ ] **Step 3: Write the migration**

`TidyShot/Output/TemplateMigration.swift`:
```swift
import Foundation

/// Rewrites naming templates saved before Phase 3.1, when `{app}` was still a token. Applied when
/// `AppSettings` loads the file name template and when `S3DestinationConfig` decodes its key
/// template, so a stored template never reaches `TemplateExpander` with `{app}` in it (it would
/// now be literal text in a file name, and an invalid key template).
nonisolated enum TemplateMigration {
    static let removedAppToken = "{app}"
    static let separators: Set<Character> = ["-", "_", ".", "/", " "]

    /// `template` without `{app}`, and without the separator the token would leave doubled or
    /// dangling: between two separators the one after the token goes (`shots/{app}-{random}`
    /// becomes `shots/{random}`), at the start the one after it (`{app} {datetime}` becomes
    /// `{datetime}`), at the end the one before it (`Screenshot {date} {app}` becomes
    /// `Screenshot {date}`). Text away from the token is never touched. A template left blank
    /// becomes `fallback`.
    static func removingAppToken(from template: String, fallback: String) -> String {
        guard template.contains(removedAppToken) else { return template }
        let token = Array(removedAppToken)
        var characters = Array(template)
        while let start = firstIndex(of: token, in: characters) {
            let end = start + token.count
            let before: Character? = start > 0 ? characters[start - 1] : nil
            let after: Character? = end < characters.count ? characters[end] : nil
            var range = start..<end
            if let after, separators.contains(after), before.map(separators.contains) ?? true {
                range = start..<(end + 1)
            } else if after == nil, let before, separators.contains(before) {
                range = (start - 1)..<end
            }
            characters.removeSubrange(range)
        }
        let result = String(characters)
        return result.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : result
    }

    private static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        return (0...(haystack.count - needle.count)).first { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}
```

- [ ] **Step 4: Take `{app}` out of the template engine and the file namer**

In `TidyShot/Output/TemplateExpander.swift`:

Replace:
```swift
/// The values a naming template is expanded against: a timestamp, the app name, a counter and
/// this Mac's host name. `FileNamer` builds one when it writes the file; object keys get one
/// when their upload starts (from the record's timestamp and app, with a freshly drawn counter).
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
```
with:
```swift
/// The values a naming template is expanded against: a timestamp, a counter and this Mac's host
/// name. `FileNamer` builds one when it writes the file; object keys get one when their upload
/// starts (from the record's timestamp, with a freshly drawn counter).
nonisolated struct TemplateContext: Sendable, Equatable {
    var date: Date
    var counter: Int
    /// Already normalised (see `TemplateExpander.normalizeHostname`).
    var hostname: String

    init(date: Date = Date(), counter: Int = 0, hostname: String = HostName.local()) {
        self.date = date
        self.counter = counter
        self.hostname = hostname
    }
}
```

Replace:
```swift
/// Tokens: `{date}` yyyy-MM-dd, `{year}`, `{month}`, `{day}`, `{time}`, `{datetime}`, `{hostname}`,
/// `{app}`, `{counter}`, `{random}` (6 characters) and `{random:N}` (1 to 64). `{time}` and
```
with:
```swift
/// Tokens: `{date}` yyyy-MM-dd, `{year}`, `{month}`, `{day}`, `{time}`, `{datetime}`, `{hostname}`,
/// `{counter}`, `{random}` (6 characters) and `{random:N}` (1 to 64). `{time}` and
```

Replace:
```swift
        case date, year, month, day, time, datetime, hostname, app, counter
```
with:
```swift
        case date, year, month, day, time, datetime, hostname, counter
```

Replace:
```swift
            case "hostname": self = .hostname
            case "app": self = .app
            case "counter": self = .counter
```
with:
```swift
            case "hostname": self = .hostname
            case "counter": self = .counter
```

Replace:
```swift
    static let tokenList = "{date} {year} {month} {day} {time} {datetime} {hostname} {app} {counter} {random} {random:8}"
```
with:
```swift
    static let tokenList = "{date} {year} {month} {day} {time} {datetime} {hostname} {counter} {random} {random:8}"
```

Replace:
```swift
    /// two captures produce different names. Without one, any two captures with the same date,
    /// app and host can produce the same name.
```
with:
```swift
    /// two captures produce different names. Without one, any two captures with the same date and
    /// host can produce the same name.
```

Replace:
```swift
        case .hostname: raw = context.hostname
        case .app: raw = context.appName ?? "Screen"
        case .counter: raw = String(context.counter)
```
with:
```swift
        case .hostname: raw = context.hostname
        case .counter: raw = String(context.counter)
```

In `TidyShot/Output/FileNamer.swift`:

Replace:
```swift
    func name(appName: String?, counter: Int) -> String {
        let context = TemplateContext(date: now(), appName: appName, counter: counter, hostname: hostname)
```
with:
```swift
    func name(counter: Int) -> String {
        let context = TemplateContext(date: now(), counter: counter, hostname: hostname)
```

- [ ] **Step 5: Migrate stored templates**

In `TidyShot/Settings/AppSettings.swift`:

Replace:
```swift
        fileNameTemplate = defaults.string(forKey: Keys.fileNameTemplate) ?? FileNamer.defaultTemplate
```
with:
```swift
        let storedFileNameTemplate = defaults.string(forKey: Keys.fileNameTemplate) ?? FileNamer.defaultTemplate
        fileNameTemplate = TemplateMigration.removingAppToken(from: storedFileNameTemplate, fallback: FileNamer.defaultTemplate)
```

Replace:
```swift
        s3Config = defaults.data(forKey: Keys.s3Config).flatMap { try? JSONDecoder().decode(S3DestinationConfig.self, from: $0) }
    }
```
with:
```swift
        // Decoding drops `{app}` from the key template (see `S3DestinationConfig.init(from:)`).
        let storedConfig = defaults.data(forKey: Keys.s3Config)
        s3Config = storedConfig.flatMap { try? JSONDecoder().decode(S3DestinationConfig.self, from: $0) }

        // Property observers do not run during init, so templates rewritten by
        // `TemplateMigration` are stored here, once.
        if fileNameTemplate != storedFileNameTemplate {
            defaults.set(fileNameTemplate, forKey: Keys.fileNameTemplate)
        }
        if let storedConfig, let s3Config,
           String(decoding: storedConfig, as: UTF8.self).contains(TemplateMigration.removedAppToken) {
            defaults.set(try? JSONEncoder().encode(s3Config), forKey: Keys.s3Config)
        }
    }
```

In `TidyShot/Upload/S3DestinationConfig.swift`:

Replace:
```swift
        if let template = try container.decodeIfPresent(String.self, forKey: .keyTemplate) {
            keyTemplate = template
        } else {
```
with:
```swift
        if let template = try container.decodeIfPresent(String.self, forKey: .keyTemplate) {
            // `{app}` was a token until Phase 3.1; a template saved with it loses it here.
            keyTemplate = TemplateMigration.removingAppToken(from: template, fallback: ObjectKeyNamer.defaultTemplate)
        } else {
```

- [ ] **Step 6: Stop passing an app name**

In `TidyShot/Upload/Destination.swift`:

Replace:
```swift
    /// What the object key template is expanded against (capture time, app, counter, hostname).
```
with:
```swift
    /// What the object key template is expanded against (capture time, counter, hostname).
```

In `TidyShot/Upload/ConnectionTester.swift`:

Replace:
```swift
        let folder = ObjectKeyNamer.folder(of: namer.makeKey(ext: "txt", context: TemplateContext(appName: "TidyShot")))
```
with:
```swift
        let folder = ObjectKeyNamer.folder(of: namer.makeKey(ext: "txt", context: TemplateContext()))
```

In `TidyShot/Settings/UploadSettingsView.swift`:

Replace:
```swift
    /// The template expanded for a capture of this Mac's frontmost app right now, with `x` for
    /// every random character.
    private var exampleKey: String {
        let context = TemplateContext(appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Safari", counter: 42)
```
with:
```swift
    /// The template expanded for a capture taken right now, with `x` for every random character.
    private var exampleKey: String {
        let context = TemplateContext(counter: 42)
```

In `TidyShot/App/AppCoordinator.swift`:

Replace:
```swift
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            await save(result, appName: frontApp)
        }
```
with:
```swift
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            await save(result)
        }
```

Replace:
```swift
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
```
with:
```swift
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: mode, content: content) else { return }

            let result: CaptureResult?
            switch selection {
            case .area(let rect, let display):
                let overlays = await selector.overlayWindows()
                result = await capture(.area(rect: rect, display: display), excludingWindows: overlays)
            case .window(let window):
                result = await capture(.window(window))
            }
            selector.dismiss()

            if let result {
                await save(result)
            }
        }
```

Replace:
```swift
    func save(_ result: CaptureResult, appName: String?) async {
```
with:
```swift
    func save(_ result: CaptureResult) async {
```

Replace:
```swift
            guard let url = await writeFile(png, result: result, appName: appName, alreadyOnClipboard: copyImageNow) else { return }
```
with:
```swift
            guard let url = await writeFile(png, result: result, alreadyOnClipboard: copyImageNow) else { return }
```

Replace:
```swift
        let record = CaptureRecord(id: id, fileURL: fileURL, fileIsTemporary: action == .uploadOnly,
                                   pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: appName, uploadState: state)
```
with:
```swift
        // The source app is no longer recorded (Phase 3.1 removed its token); older records keep theirs.
        let record = CaptureRecord(id: id, fileURL: fileURL, fileIsTemporary: action == .uploadOnly,
                                   pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: nil, uploadState: state)
```

Replace:
```swift
    private func writeFile(_ png: Data, result: CaptureResult, appName: String?, alreadyOnClipboard: Bool) async -> URL? {
```
with:
```swift
    private func writeFile(_ png: Data, result: CaptureResult, alreadyOnClipboard: Bool) async -> URL? {
```

Replace:
```swift
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: counter)
```
with:
```swift
            let baseName = FileNamer(template: settings.fileNameTemplate).name(counter: counter)
```

Replace:
```swift
        // up, and every retry, get a counter drawn when their upload starts. The date and app stay
        // the capture's own, so a retried upload lands in the capture's date folder.
        let counter = lane.keyTemplate.contains("{counter}") ? settings.nextCounter() : 0
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            naming: TemplateContext(date: record.timestamp, appName: record.appName, counter: counter))
```
with:
```swift
        // up, and every retry, get a counter drawn when their upload starts. The date stays the
        // capture's own, so a retried upload lands in the capture's date folder.
        let counter = lane.keyTemplate.contains("{counter}") ? settings.nextCounter() : 0
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            naming: TemplateContext(date: record.timestamp, counter: counter))
```

- [ ] **Step 7: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 168 tests in 25 suites passed` (161 + 4 TemplateMigrationTests + 1 TemplateExpanderTests + 1 AppSettingsTests + 1 S3DestinationConfigTests; FileNamerTests keeps 12, ObjectKeyNamerTests 13).

Then confirm the token is gone from the app and its captions:
```bash
grep -rn "{app}" TidyShot | grep -v "TidyShot/Output/TemplateMigration.swift" | grep -v "TidyShot/Settings/AppSettings.swift" | grep -v "TidyShot/Upload/S3DestinationConfig.swift"
```
Expected: no output (the three excluded files mention it only in the migration and its comments).

- [ ] **Step 8: Update the README and the earlier checklists**

In `README.md`:

Replace:
```markdown
`{day}` `{time}` `{datetime}` `{hostname}` `{app}` `{counter}` `{random}` `{random:N}`; letters,
```
with:
```markdown
`{day}` `{time}` `{datetime}` `{hostname}` `{counter}` `{random}` `{random:N}`; letters,
```

In `docs/testing/phase-1-manual-checklist.md`:

Replace:
```markdown
- [ ] Dragging draws nothing; release over a window captures it.
- [ ] `{app}` resolves to the window's app.
```
with:
```markdown
- [ ] Dragging draws nothing; release over a window captures it.
```

In `docs/testing/phase-3-manual-checklist.md`:

Replace:
```markdown
- [ ] Template `{date}/{app}`: the orange warning appears and says the template has no {random} or {counter}, so captures can produce the same key and only the HEAD check keeps a capture from overwriting an earlier object; Save works; two captures of the same app on the same day: the second fails with "Could not find an unused object key after 5 tries." and keeps its file for retry.
```
with:
```markdown
- [ ] Template `{date}/{hostname}`: the orange warning appears and says the template has no {random} or {counter}, so captures can produce the same key and only the HEAD check keeps a capture from overwriting an earlier object; Save works; two captures on the same day: the second fails with "Could not find an unused object key after 5 tries." and keeps its file for retry.
```

Replace:
```markdown
- [ ] File name template `{year}-{month}-{day} {hostname} {app}` names local files as expected; the default template still gives `Screenshot 2026-10-19 at 11.56.03.png`.
```
with:
```markdown
- [ ] File name template `{year}-{month}-{day} {hostname}` names local files as expected; the default template still gives `Screenshot 2026-10-19 at 11.56.03.png`.
```

Then:
```bash
grep -rn "{app}" README.md docs/testing
```
Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add TidyShot/Output/TemplateMigration.swift TidyShotTests/TemplateMigrationTests.swift TidyShot/Output/TemplateExpander.swift TidyShot/Output/FileNamer.swift TidyShot/Settings/AppSettings.swift TidyShot/Upload/S3DestinationConfig.swift TidyShot/Upload/Destination.swift TidyShot/Upload/ConnectionTester.swift TidyShot/Settings/UploadSettingsView.swift TidyShot/App/AppCoordinator.swift TidyShotTests/TemplateExpanderTests.swift TidyShotTests/FileNamerTests.swift TidyShotTests/ObjectKeyNamerTests.swift TidyShotTests/UploadQueueTests.swift TidyShotTests/AppSettingsTests.swift TidyShotTests/S3DestinationConfigTests.swift README.md docs/testing/phase-1-manual-checklist.md docs/testing/phase-3-manual-checklist.md
git commit -m "feat: remove the {app} token and migrate stored templates"
```

---

### Task 2: Clearer Upload fields and a connection test result without the probe URL (TDD for the summary)

**Files:**
- Modify: `TidyShot/Upload/ConnectionTester.swift` (one edit)
- Modify: `TidyShot/Settings/UploadSettingsView.swift` (two edits)
- Modify, only if the Upload tab now scrolls: `TidyShot/Settings/SettingsView.swift` (Step 6)
- Test: `TidyShotTests/ConnectionTesterTests.swift` (one new test)

**Interfaces:**
- Consumes: `ConnectionTestResult` (Phase 2).
- Produces: `ConnectionTestResult.summary` for `.readable` is exactly `Upload and public read both work.`; the other outcomes are unchanged. The Endpoint and Public URL fields show the prompt `Required`, each with a caption line `Example: https://s3.us-west-2.amazonaws.com` and `Example: https://snap.tky.io/{key}`.

- [ ] **Step 1: Write the failing test**

In `TidyShotTests/ConnectionTesterTests.swift`:

Replace:
```swift
        #expect(requests[1].value(forHTTPHeaderField: "authorization") == nil)
    }
```
with:
```swift
        #expect(requests[1].value(forHTTPHeaderField: "authorization") == nil)
    }

    /// The probe is deleted by the time the result shows, so its URL is not echoed.
    @Test func readableSummaryDoesNotEchoTheProbeURL() {
        let result = ConnectionTestResult(probeKey: "p/tidyshot-probe-ZZZZZZZZ.txt",
                                          publicURL: URL(string: "https://snap.tky.io/p/tidyshot-probe-ZZZZZZZZ.txt"),
                                          outcome: .readable)
        #expect(result.summary == "Upload and public read both work.")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "✘|Test run"
```
Expected: `✘ Test readableSummaryDoesNotEchoTheProbeURL() recorded an issue at ConnectionTesterTests.swift:…: Expectation failed: result.summary == "Upload and public read both work."` (the summary still ends with the URL), and `✘ Test run with 169 tests in 25 suites failed … with 1 issue.`

- [ ] **Step 3: Drop the URL from the summary**

In `TidyShot/Upload/ConnectionTester.swift`:

Replace:
```swift
            "Upload and public read both work. \(publicURL?.absoluteString ?? "")"
```
with:
```swift
            "Upload and public read both work."
```

- [ ] **Step 4: Neutral prompts with example captions**

In `TidyShot/Settings/UploadSettingsView.swift`:

Replace:
```swift
                TextField("Endpoint", text: $draft.endpoint, prompt: Text("https://s3.us-west-2.amazonaws.com"))
```
with:
```swift
                // A prompt that looks like a value reads as filled in; the example goes underneath.
                TextField("Endpoint", text: $draft.endpoint, prompt: Text("Required"))
                Text("Example: https://s3.us-west-2.amazonaws.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

Replace:
```swift
                TextField("Public URL", text: $draft.publicURLTemplate, prompt: Text("https://snap.tky.io/{key}"))
                Text("{key} is replaced with the full object key, including any folders from the key template.")
```
with:
```swift
                TextField("Public URL", text: $draft.publicURLTemplate, prompt: Text("Required"))
                Text("Example: https://snap.tky.io/{key}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("{key} is replaced with the full object key, including any folders from the key template.")
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 169 tests in 25 suites passed`.

- [ ] **Step 6: Check the Upload tab (conditional)**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Open Settings > Upload (the SwiftUI menu bar item still works in this task). Expected: an empty Endpoint and Public URL field shows the grey word "Required", the example sits on its own caption line under each field, and the tab still shows everything down to the Save buttons without scrolling when you type `{date}/{hostname}` into the key template (the orange warning showing). Only if the tab now scrolls: in `TidyShot/Settings/SettingsView.swift` change `.frame(width: 600, height: 800)` to `.frame(width: 600, height: 840)`, rebuild, check again, and add `TidyShot/Settings/SettingsView.swift` to the `git add` in Step 7. Put the key template back and quit without saving.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Upload/ConnectionTester.swift TidyShot/Settings/UploadSettingsView.swift TidyShotTests/ConnectionTesterTests.swift
git commit -m "feat: Required prompts with example captions; test result without the probe URL"
```

---

### Task 3: Two-button delete confirmation, with "remove from history anyway" after a failed storage DELETE (TDD for the texts)

**Files:**
- Modify: `TidyShot/History/CaptureDeletion.swift` (full replacement)
- Modify: `TidyShot/App/AppCoordinator.swift` (edits below)
- Test: `TidyShotTests/CaptureDeletionTests.swift` (full replacement)

**Interfaces:**
- Consumes: `CaptureDeletion.objectKeys(for:)`, `CaptureDeletion.sharedKeys(_:at:with:)`, `AppCoordinator.cancelUpload(of:)`, `removeRecord(id:)`, `removePendingFile(at:context:failureTitle:)`, `loadCredentials()` (Phase 3).
- Produces:
  - `CaptureDeletion.confirmationMessage` (`Delete this capture?`), `CaptureDeletion.confirmationText(for: CaptureRecord) -> String` (one line), `CaptureDeletion.storageFailureMessage(reason: String) -> String` (`Couldn't delete it from storage: <reason>`), `CaptureDeletion.storageFailureText` (`Remove it from history anyway? The object stays in the bucket.`). `historyOnlyNote` is gone.
  - `AppCoordinator.deleteCapture(recordID:)` keeps its signature and stays the only delete path. Its first alert has the buttons Delete (destructive) and Cancel; a failed storage `DELETE`, or missing credentials, shows a second alert with Remove (destructive) and Cancel, and Remove drops the record, its thumbnail and a temporary file in `pending`, leaving the object and any file in the save folder. `DeleteChoice` is removed.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/CaptureDeletionTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct CaptureDeletionTests {
    let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap.tky.io", usePathStyle: true)

    func record(state: CaptureRecord.UploadState, fileURL: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                temporary: Bool = false, location: ObjectLocation? = nil, pendingKey: String? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: "Safari",
                      uploadState: state, objectLocation: location, pendingObjectKey: pendingKey)
    }

    @Test func objectKeysAreTheUploadedAndThePendingKey() {
        let uploaded = record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location)
        #expect(CaptureDeletion.objectKeys(for: uploaded) == ["aB3dE9.png"])

        let cancelled = record(state: .failed(message: "Upload cancelled."), location: location, pendingKey: "Qx12Zz.png")
        #expect(CaptureDeletion.objectKeys(for: cancelled) == ["Qx12Zz.png"])

        let both = record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location, pendingKey: "Qx12Zz.png")
        #expect(CaptureDeletion.objectKeys(for: both) == ["aB3dE9.png", "Qx12Zz.png"])

        let same = record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location, pendingKey: "aB3dE9.png")
        #expect(CaptureDeletion.objectKeys(for: same) == ["aB3dE9.png"])
    }

    @Test func objectKeysForLocalOnlyCaptureAreEmpty() {
        #expect(CaptureDeletion.objectKeys(for: record(state: .none)) == [])
        #expect(CaptureDeletion.objectKeys(for: record(state: .failed(message: "offline"))) == [])
        #expect(CaptureDeletion.objectKeys(for: record(state: .uploading(fraction: 0.5))) == [])
    }

    @Test func sharedKeysAreTheOnesAnotherCaptureUsesAtTheSameLocation() {
        var otherBucket = location
        otherBucket.bucket = "elsewhere"
        let others = [
            record(state: .uploaded(url: url, key: "same.png"), location: location),
            record(state: .uploaded(url: url, key: "moved.png"), location: otherBucket),
            record(state: .failed(message: "Upload cancelled."), location: location, pendingKey: "reserved.png"),
            record(state: .uploaded(url: url, key: "legacy.png")),
        ]
        #expect(CaptureDeletion.sharedKeys(["same.png", "moved.png", "reserved.png", "legacy.png", "mine.png"], at: location, with: others)
                == ["same.png", "reserved.png"])
        #expect(CaptureDeletion.sharedKeys(["same.png"], at: location, with: []) == [])
    }

    /// One line saying where the capture disappears from. Delete also removes the thumbnail.
    @Test func confirmationTextIsOneLine() {
        let storage = "Removes it from object storage and from history."
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location)) == storage)
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png"), fileURL: nil, location: location)) == storage)
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploading(fraction: 0.2), fileURL: URL(fileURLWithPath: "/tmp/p.png"), temporary: true)) == storage)
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "Upload cancelled."), fileURL: nil, location: location, pendingKey: "Qx12Zz.png")) == storage)
        #expect(CaptureDeletion.confirmationText(for: record(state: .none)) == "Removes it from your save folder and from history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "offline"), fileURL: URL(fileURLWithPath: "/tmp/p.png"), temporary: true))
                == "Removes it from history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "x"), fileURL: nil)) == "Removes it from history.")
    }

    /// A Phase 2 record does not know which bucket its object went to, so Delete leaves it.
    @Test func confirmationTextSaysWhenTheObjectStays() {
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png")))
                == "Removes it from your save folder and from history. The uploaded object stays in the bucket.")
    }

    @Test func alertTexts() {
        #expect(CaptureDeletion.confirmationMessage == "Delete this capture?")
        #expect(CaptureDeletion.storageFailureMessage(reason: "Server returned HTTP 403: AccessDenied: Access Denied")
                == "Couldn't delete it from storage: Server returned HTTP 403: AccessDenied: Access Denied")
        #expect(CaptureDeletion.storageFailureText == "Remove it from history anyway? The object stays in the bucket.")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `type 'CaptureDeletion' has no member 'confirmationMessage'`.

- [ ] **Step 3: Write the texts**

`TidyShot/History/CaptureDeletion.swift`:
```swift
import Foundation

/// The pure parts of deleting a capture, shared by the overlay and Recent Captures: which objects
/// to remove from the bucket, which of them another capture still needs, and what the two alerts
/// say. `AppCoordinator.deleteCapture` does the I/O.
nonisolated enum CaptureDeletion {
    /// The first alert's message. Its buttons are Delete and Cancel.
    static let confirmationMessage = "Delete this capture?"
    /// The second alert's informative text, shown only after the storage DELETE failed. Its buttons
    /// are Remove and Cancel.
    static let storageFailureText = "Remove it from history anyway? The object stays in the bucket."

    /// Object keys that may hold the capture, in order and without duplicates: the key it was
    /// uploaded under, and the key a cancelled upload had reserved (its PUT may have completed
    /// on the server as it was cancelled). Both live at `record.objectLocation`.
    static func objectKeys(for record: CaptureRecord) -> [String] {
        var keys: [String] = []
        for key in [record.uploadedKey, record.pendingObjectKey].compactMap({ $0 }) where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    /// The keys among `keys` that a record in `others` also points at, at the same location.
    /// A template without `{random}` or `{counter}` can give two captures the same key when HEAD
    /// cannot see the first object, and deleting it would break the other capture's URL.
    static func sharedKeys(_ keys: [String], at location: ObjectLocation, with others: [CaptureRecord]) -> [String] {
        keys.filter { key in
            others.contains { other in
                other.objectLocation == location && (other.uploadedKey == key || other.pendingObjectKey == key)
            }
        }
    }

    /// The first alert's one line: where the capture disappears from. Delete also removes the
    /// thumbnail, and the local file when the object is in storage too. A record uploaded before
    /// Phase 3 has no `objectLocation`, so its object cannot be deleted, and the line says it stays.
    static func confirmationText(for record: CaptureRecord) -> String {
        if record.isUploading || (record.objectLocation != nil && !objectKeys(for: record).isEmpty) {
            return "Removes it from object storage and from history."
        }
        let inSaveFolder = record.fileURL != nil && !record.fileIsTemporary
        var text = inSaveFolder ? "Removes it from your save folder and from history." : "Removes it from history."
        if record.uploadedURL != nil {
            text += " The uploaded object stays in the bucket."
        }
        return text
    }

    /// The second alert's message, after the storage DELETE failed with `reason`.
    static func storageFailureMessage(reason: String) -> String {
        "Couldn't delete it from storage: \(reason)"
    }
}
```

- [ ] **Step 4: Two alerts in the delete path**

In `TidyShot/App/AppCoordinator.swift`:

Replace:
```swift
    /// The buttons of the delete confirmation.
    private enum DeleteChoice {
        case delete
        case removeFromHistoryOnly
        case cancel
    }

    static let shared = AppCoordinator()
```
with:
```swift
    static let shared = AppCoordinator()
```

Replace:
```swift
    /// Shared by the overlay and the gallery. One confirmation with three answers. Delete stops
    /// an in-flight upload, removes the object from the bucket the record says it went to, then
    /// the local file, the thumbnail and the record. A failed `DELETE` or a local file that
    /// cannot be removed keeps the record, with a notification, so Delete can be tried again; a
    /// local file that is already gone is not an error. "Remove from History Only" drops just the
    /// record, for a capture whose object can no longer be deleted.
    func deleteCapture(recordID: UUID) async {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        deletingIDs.insert(recordID)
        defer { deletingIDs.remove(recordID) }

        switch confirmDelete(of: record) {
        case .cancel:
            return
        case .removeFromHistoryOnly:
            // Stop an upload still running so it cannot finish for a record that is gone. Nothing
            // in the bucket or the save folder is touched; a temporary file in `pending` is
            // TidyShot's own copy that nothing else would ever remove, so it goes with the record.
            await cancelUpload(of: recordID)
            guard let current = history.record(id: recordID) else { return }
            // If the temporary file cannot be removed the record is kept, as Delete does, so the
            // file is not left behind with nothing pointing at it.
            if current.fileIsTemporary, let fileURL = current.fileURL,
               !removePendingFile(at: fileURL, context: "on remove from history", failureTitle: "Not removed") {
                return
            }
            removeRecord(id: recordID)
            return
        case .delete:
            break
        }
```
with:
```swift
    /// The one delete path, shared by the overlay and Recent Captures. One confirmation, Delete or
    /// Cancel. Delete stops an in-flight upload, removes the object from the bucket the record says
    /// it went to, then the local file, the thumbnail and the record. When the storage `DELETE`
    /// fails (or there are no credentials to sign it) a second alert offers to remove the record
    /// from history anyway, so a capture whose object cannot be deleted is never stuck. A local
    /// file that cannot be removed keeps the record, with a notification; one that is already gone
    /// is not an error.
    func deleteCapture(recordID: UUID) async {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        deletingIDs.insert(recordID)
        defer { deletingIDs.remove(recordID) }
        guard confirmDelete(of: record) else { return }
```

Replace:
```swift
        if !keys.isEmpty, let location = current.objectLocation {
            guard let credentials = loadCredentials() else {
                notifier.notifyError("Save credentials in Settings > Upload so the uploaded object can be removed, then try again, or choose Remove from History Only.",
                                     title: "Not deleted")
                return
            }
            // Never delete an object another capture still points at.
            // A record whose own delete is still pending (its alert open) counts as a sharer: if
            // that delete is cancelled, its URL must keep working.
            let others = history.records.filter { $0.id != recordID }
            sharedKeys = CaptureDeletion.sharedKeys(keys, at: location, with: others)
            // Built from where the object went, not from the current Upload settings.
            let destination = S3Destination(config: location.config, credentials: credentials)
            for key in keys where !sharedKeys.contains(key) {
                do {
                    try await destination.delete(key: key)
                } catch {
                    notifier.notifyError("Could not delete \(key): \(error.localizedDescription)", title: "Not deleted")
                    return
                }
            }
        }
```
with:
```swift
        if !keys.isEmpty, let location = current.objectLocation {
            // Never delete an object another capture still points at.
            // A record whose own delete is still pending (its alert open) counts as a sharer: if
            // that delete is cancelled, its URL must keep working.
            let others = history.records.filter { $0.id != recordID }
            sharedKeys = CaptureDeletion.sharedKeys(keys, at: location, with: others)
            if let reason = await deleteObjects(keys.filter { !sharedKeys.contains($0) }, at: location) {
                if confirmRemoveFromHistory(afterStorageFailure: reason) {
                    removeFromHistoryOnly(recordID)
                }
                return
            }
        }
```

Replace:
```swift
        for key in sharedKeys {
            notifier.notifyError("Another capture shares this key, \(key), so its object was kept. This capture was removed from Recent Captures.",
                                 title: "Not deleted from storage")
        }
    }
```
with:
```swift
        for key in sharedKeys {
            notifier.notifyError("Another capture shares this key, \(key), so its object was kept. This capture was removed from Recent Captures.",
                                 title: "Not deleted from storage")
        }
    }

    /// `DELETE`s `keys` at `location`, signed with the credentials stored now; the destination is
    /// built from where the object went, never from the current Upload settings. Returns nil when
    /// every key is gone (a 404 counts as gone), otherwise the reason for the first failure.
    private func deleteObjects(_ keys: [String], at location: ObjectLocation) async -> String? {
        guard !keys.isEmpty else { return nil }
        guard let credentials = loadCredentials() else {
            return "No credentials are saved in Settings > Upload."
        }
        let destination = S3Destination(config: location.config, credentials: credentials)
        for key in keys {
            do {
                try await destination.delete(key: key)
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    /// The second alert's Remove: drops the record and its thumbnail without touching storage or a
    /// file in the save folder (the delete already cancelled any upload). A temporary file in
    /// `pending` is TidyShot's own copy that nothing else would ever remove, so it goes too; if it
    /// cannot be removed the record is kept, so the file is not left with nothing pointing at it.
    private func removeFromHistoryOnly(_ recordID: UUID) {
        guard let current = history.record(id: recordID) else { return }
        if current.fileIsTemporary, let fileURL = current.fileURL,
           !removePendingFile(at: fileURL, context: "on remove from history", failureTitle: "Not removed") {
            return
        }
        removeRecord(id: recordID)
    }
```

Replace:
```swift
    /// The one confirmation. The app is activated first so the alert appears in front even when
    /// it was triggered from the non-activating overlay panel.
    private func confirmDelete(of record: CaptureRecord) -> DeleteChoice {
        let alert = NSAlert()
        alert.messageText = "Delete this capture?"
        alert.informativeText = CaptureDeletion.confirmationText(for: record)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Remove from History Only")
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .delete
        case .alertSecondButtonReturn: return .removeFromHistoryOnly
        default: return .cancel
        }
    }
```
with:
```swift
    /// The confirmation: Delete or Cancel (Escape). The app is activated first so the alert appears
    /// in front even when it was triggered from the non-activating overlay panel or the menu.
    private func confirmDelete(of record: CaptureRecord) -> Bool {
        let alert = NSAlert()
        alert.messageText = CaptureDeletion.confirmationMessage
        alert.informativeText = CaptureDeletion.confirmationText(for: record)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Only after the storage `DELETE` failed: Remove (from history; the object stays) or Cancel.
    private func confirmRemoveFromHistory(afterStorageFailure reason: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = CaptureDeletion.storageFailureMessage(reason: reason)
        alert.informativeText = CaptureDeletion.storageFailureText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 170 tests in 25 suites passed` (CaptureDeletionTests goes from 5 to 6: the two Phase 3 text tests are replaced by `confirmationTextIsOneLine` and `confirmationTextSaysWhenTheObjectStays`, plus `alertTexts`).

- [ ] **Step 6: Check both alerts by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Capture an area with a working destination and click the overlay's trash button. Expected: "Delete this capture?", "Removes it from object storage and from history.", buttons Delete and Cancel; Escape cancels; Delete removes the object (`curl -I <url>` gives 403 or 404). Then take another capture that uploads, turn Wi-Fi off, open Recent Captures… and choose Delete… on it, then Delete: a second alert reads "Couldn't delete it from storage: …" with "Remove it from history anyway? The object stays in the bucket." and the buttons Remove and Cancel. Cancel keeps the capture. Delete… again, Delete, Remove: the capture leaves the gallery, its file stays in the save folder, and with Wi-Fi back on `curl -I <url>` still gives 200.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/History/CaptureDeletion.swift TidyShot/App/AppCoordinator.swift TidyShotTests/CaptureDeletionTests.swift
git commit -m "feat: two-button delete alert; remove from history only after a failed storage delete"
```

---

### Task 4: Signed GET and Copy Image (TDD for the download request and PNG decoding)

**Files:**
- Modify: `TidyShot/Upload/S3Destination.swift` (two edits)
- Modify: `TidyShot/Output/ImageEncoder.swift` (one edit)
- Modify: `TidyShot/Output/Notifier.swift` (one edit)
- Modify: `TidyShot/App/AppCoordinator.swift` (two edits)
- Test: `TidyShotTests/S3DestinationTests.swift` (two new tests), `TidyShotTests/ImageEncoderTests.swift` (one new test)

**Interfaces:**
- Consumes: `S3Destination.signedRequest(method:key:body:extraHeaders:)`, `UploadProgressDelegate` (refuses redirects), `AppCoordinator.readLocalFile(of:)`, `loadCredentials()`, `ObjectLocation.config`, `Pasteboard.copy(image:pngData:scale:)` (Phase 2 and 3).
- Produces:
  - `S3Destination.download(key: String) async throws -> Data`: signed GET; 2xx returns the body, anything else throws `UploadError.httpStatus` with the same summarised body as PUT (a 404 is an error here, unlike `delete`).
  - `ImageEncoder.decode(_ data: Data) -> (image: CGImage, scale: CGFloat)?`: the scale is read back from the DPI that `pngData(from:scale:)` writes (144 DPI gives 2), 1 when there is none.
  - `Notifier.notify(title: String, body: String)`: a plain notification with no click action.
  - `AppCoordinator.copyImage(recordID: UUID) async`: local file when it can be read, otherwise a download (with "Copying image…" while it runs); "Image copied" on success (both only when Show notification is on), "Could not copy image" with the reason on failure.
  - `nonisolated enum CopyImageError: LocalizedError { case nothingToCopy, notAnImage }` at the end of `AppCoordinator.swift`.

- [ ] **Step 1: Write the failing tests**

In `TidyShotTests/S3DestinationTests.swift`:

Replace:
```swift
    @Test func errorBodyIsSummarisedFromS3XML() async throws {
```
with:
```swift
    /// Copy Image downloads upload-only captures. Expected signature computed independently with
    /// a reference implementation.
    @Test func downloadIsASignedGetThatReturnsTheBody() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let (session, stub) = StubSession.make { _ in (200, png) }
        let data = try await destination(config, session: session).download(key: "aSIS7.png")

        #expect(data == png)
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://snap.s3.us-east-1.amazonaws.com/aSIS7.png")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == S3Signer.emptyPayloadHash)
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=2b2032e36f0ecee5dda47c71b2b5cb033deed81114e1626e47639929cb0f7162")
    }

    @Test func downloadThrowsTheSummarisedErrorOnFailure() async throws {
        let xml = "<Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message></Error>"
        let (session, stub) = StubSession.make { _ in (404, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(404, body: "NoSuchKey: The specified key does not exist.")) {
            try await destination(config, session: session).download(key: "gone.png")
        }
        #expect(stub.requests.map(\.httpMethod) == ["GET"])
    }

    @Test func errorBodyIsSummarisedFromS3XML() async throws {
```

In `TidyShotTests/ImageEncoderTests.swift`:

Replace:
```swift
    @Test func standardScaleWrites72DPI() throws {
        let data = try ImageEncoder.pngData(from: makeImage(width: 10, height: 10), scale: 1)
        let props = properties(of: data)
        #expect(abs(dpi(props, kCGImagePropertyDPIWidth) - 72) < 0.5)
    }
```
with:
```swift
    @Test func standardScaleWrites72DPI() throws {
        let data = try ImageEncoder.pngData(from: makeImage(width: 10, height: 10), scale: 1)
        let props = properties(of: data)
        #expect(abs(dpi(props, kCGImagePropertyDPIWidth) - 72) < 0.5)
    }

    /// Copy Image pastes at point size, so the scale comes back from the DPI.
    @Test func decodeReadsBackTheScale() throws {
        let retina = try #require(ImageEncoder.decode(try ImageEncoder.pngData(from: makeImage(width: 200, height: 100), scale: 2)))
        #expect(retina.image.width == 200)
        #expect(retina.image.height == 100)
        #expect(retina.scale == 2)
        #expect(ImageEncoder.decode(try ImageEncoder.pngData(from: makeImage(width: 10, height: 10), scale: 1))?.scale == 1)
        #expect(ImageEncoder.decode(Data("not a png".utf8)) == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `value of type 'S3Destination' has no member 'download'` or `type 'ImageEncoder' has no member 'decode'`.

- [ ] **Step 3: Write the download and the decoder**

In `TidyShot/Upload/S3Destination.swift`:

Replace:
```swift
/// PUT, HEAD and DELETE Object over URLSession with SigV4 headers. Works with AWS S3,
/// Cloudflare R2, Backblaze B2 and MinIO, which all speak the same three requests.
```
with:
```swift
/// PUT, HEAD, GET and DELETE Object over URLSession with SigV4 headers. Works with AWS S3,
/// Cloudflare R2, Backblaze B2 and MinIO, which all speak the same four requests.
```

Replace:
```swift
    func publicURL(for key: String) throws -> URL {
        try config.publicURL(for: key)
    }
```
with:
```swift
    /// GET Object, signed like the other requests (the bucket need not be public). Copy Image uses
    /// it for captures that have no local file. Unlike `delete`, a 404 is an error: there is
    /// nothing to copy.
    func download(key: String) async throws -> Data {
        let request = try signedRequest(method: "GET", key: key, body: nil, extraHeaders: [])
        let (body, response) = try await session.data(for: request, delegate: UploadProgressDelegate())
        let http = try Self.httpResponse(response)
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(http, bodyText: Self.excerpt(body))
        }
        return body
    }

    func publicURL(for key: String) throws -> URL {
        try config.publicURL(for: key)
    }
```

In `TidyShot/Output/ImageEncoder.swift`:

Replace:
```swift
        guard CGImageDestinationFinalize(destination) else {
            throw EncodeError.finalizeFailed
        }
        return data as Data
    }
```
with:
```swift
        guard CGImageDestinationFinalize(destination) else {
            throw EncodeError.finalizeFailed
        }
        return data as Data
    }

    /// Decodes PNG bytes (a capture's file, or its object downloaded for Copy Image) and reads the
    /// scale back from the DPI that `pngData(from:scale:)` writes: 144 DPI gives 2, and no DPI
    /// gives 1. PNG stores pixels per metre, so the DPI comes back a fraction off and is rounded.
    /// Nil when the bytes are not an image.
    static func decode(_ data: Data) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 72
        return (image, max(1, (dpi / 72).rounded()))
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 173 tests in 25 suites passed`.

- [ ] **Step 5: Add Copy Image to the coordinator**

In `TidyShot/Output/Notifier.swift`:

Replace:
```swift
    func notifyError(_ message: String, title: String = "Capture failed") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        post(content)
    }
```
with:
```swift
    func notifyError(_ message: String, title: String = "Capture failed") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        post(content)
    }

    /// A plain notification with no click action, such as "Copying image…" and "Image copied".
    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        post(content)
    }
```

In `TidyShot/App/AppCoordinator.swift`:

Replace:
```swift
    func reveal(recordID: UUID) {
```
with:
```swift
    /// Copy Image: the PNG and TIFF on the clipboard, from the local file when it can be read;
    /// otherwise (an upload-only capture) downloaded with a signed GET from the bucket the record
    /// says it went to, with "Copying image…" posted while that runs.
    func copyImage(recordID: UUID) async {
        guard let record = history.record(id: recordID) else { return }
        do {
            let png: Data
            if let local = try? readLocalFile(of: record) {
                png = local
            } else {
                png = try await downloadImage(of: record)
            }
            guard let decoded = ImageEncoder.decode(png) else { throw CopyImageError.notAnImage }
            Pasteboard.copy(image: decoded.image, pngData: png, scale: decoded.scale)
            if settings.showNotification {
                notifier.notify(title: "Image copied", body: record.uploadedKey ?? record.fileURL?.lastPathComponent ?? "")
            }
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Could not copy image")
        }
    }

    /// The uploaded object's bytes, from where the record says it went, signed with the
    /// credentials stored now.
    private func downloadImage(of record: CaptureRecord) async throws -> Data {
        guard let key = record.uploadedKey, let location = record.objectLocation else { throw CopyImageError.nothingToCopy }
        guard let credentials = loadCredentials() else { throw UploadError.notConfigured }
        if settings.showNotification {
            notifier.notify(title: "Copying image…", body: "Downloading \(key)")
        }
        return try await S3Destination(config: location.config, credentials: credentials).download(key: key)
    }

    func reveal(recordID: UUID) {
```

Replace:
```swift
        return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
    }
}
```
with:
```swift
        return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
    }
}

/// Why Copy Image had nothing to put on the clipboard.
nonisolated enum CopyImageError: LocalizedError, Equatable, Sendable {
    case nothingToCopy
    case notAnImage

    var errorDescription: String? {
        switch self {
        case .nothingToCopy: "The capture has no local file, and TidyShot does not know where its upload went."
        case .notAnImage: "The file is not an image TidyShot can read."
        }
    }
}
```

- [ ] **Step 6: Build and run the tests**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 173 tests in 25 suites passed`. Copy Image has no menu item until Task 7; its manual checks are in the Phase 3.1 checklist (Task 9).

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Upload/S3Destination.swift TidyShot/Output/ImageEncoder.swift TidyShot/Output/Notifier.swift TidyShot/App/AppCoordinator.swift TidyShotTests/S3DestinationTests.swift TidyShotTests/ImageEncoderTests.swift
git commit -m "feat: signed GET download and Copy Image"
```

---

### Task 5: Adaptive crosshair colour (TDD for the luminance sampling)

**Files:**
- Create: `TidyShot/Selection/Luminance.swift`
- Create: `TidyShotTests/LuminanceTests.swift`
- Modify: `TidyShot/Selection/SelectionView.swift` (edits below)

**Interfaces:**
- Consumes: `SelectionView.snapshot` and `snapshotScale` (Phase 1: the frozen display image in pixels, set by `SelectionController` a moment after the overlay appears).
- Produces:
  - `nonisolated enum Luminance { static let sampleSide: CGFloat; static func mean(of image: CGImage, in rect: CGRect) -> Double? }`: `rect` in image pixels, origin top left (as `CGImage.cropping(to:)`); clipped to the image; nil when nothing is left.
  - `nonisolated enum CrosshairStyle: Equatable, Sendable { case dark, light, outlined; init(luminance: Double?) }`: above 0.5 is `.dark` (black at 0.8 alpha), otherwise `.light` (white at 0.8 alpha); no sample is `.outlined` (white with a one-pixel black edge beneath).
  - `SelectionView` keeps a `crosshairStyle`, recomputed on mouse moves, drags and when the snapshot arrives, and strokes the crosshair, the drag rectangle border and the completed rectangle border with it.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/LuminanceTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct LuminanceTests {
    /// A `width` by `height` sRGB image; `paint` draws in CoreGraphics coordinates (origin bottom left).
    func image(width: Int = 40, height: Int = 40, _ paint: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        paint(context)
        return context.makeImage()!
    }

    func filled(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
        image { context in
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    let whole = CGRect(x: 0, y: 0, width: 40, height: 40)

    @Test func whiteIsOneAndBlackIsZero() throws {
        #expect(abs(try #require(Luminance.mean(of: filled(1, 1, 1), in: whole)) - 1) < 0.01)
        #expect(abs(try #require(Luminance.mean(of: filled(0, 0, 0), in: whole))) < 0.01)
    }

    @Test func greenWeighsMostAsInRec709() throws {
        #expect(abs(try #require(Luminance.mean(of: filled(0, 1, 0), in: whole)) - 0.7152) < 0.01)
        #expect(abs(try #require(Luminance.mean(of: filled(0, 0, 1), in: whole)) - 0.0722) < 0.01)
    }

    /// Top half white in the image means the first 20 rows of `rect` coordinates, which start at the top.
    @Test func rectIsMeasuredFromTheTopLeft() throws {
        let topWhite = image { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 20, width: 40, height: 20))
        }
        #expect(abs(try #require(Luminance.mean(of: topWhite, in: CGRect(x: 0, y: 0, width: 40, height: 20))) - 1) < 0.01)
        #expect(abs(try #require(Luminance.mean(of: topWhite, in: CGRect(x: 0, y: 20, width: 40, height: 20)))) < 0.01)
        #expect(abs(try #require(Luminance.mean(of: topWhite, in: whole)) - 0.5) < 0.02)
    }

    @Test func rectOutsideTheImageIsClippedOrNil() throws {
        // Only the visible 10 by 10 pixels at the top left count.
        #expect(abs(try #require(Luminance.mean(of: filled(1, 1, 1), in: CGRect(x: -30, y: -30, width: 40, height: 40))) - 1) < 0.01)
        #expect(Luminance.mean(of: filled(1, 1, 1), in: CGRect(x: 50, y: 50, width: 10, height: 10)) == nil)
    }

    /// A 2x snapshot samples 48 by 48 pixels; the buffer stays at 32 by 32 at most.
    @Test func largeRectsAreDownsampledToTheSameMean() throws {
        let big = image(width: 400, height: 400) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 200, y: 0, width: 200, height: 400))
        }
        #expect(abs(try #require(Luminance.mean(of: big, in: CGRect(x: 0, y: 0, width: 400, height: 400))) - 0.5) < 0.03)
    }

    @Test func crosshairStyleThresholds() {
        #expect(CrosshairStyle(luminance: nil) == .outlined)
        #expect(CrosshairStyle(luminance: 0.51) == .dark)
        #expect(CrosshairStyle(luminance: 1) == .dark)
        #expect(CrosshairStyle(luminance: 0.5) == .light)
        #expect(CrosshairStyle(luminance: 0) == .light)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `cannot find 'Luminance' in scope`.

- [ ] **Step 3: Write the sampler**

`TidyShot/Selection/Luminance.swift`:
```swift
import CoreGraphics

/// How light the frozen screen is around the cursor, so the selection crosshair can be drawn in a
/// colour that shows up on it.
nonisolated enum Luminance {
    /// The side of the square sampled around the cursor, in points.
    static let sampleSide: CGFloat = 24
    /// The sample buffer's largest side; a bigger crop is drawn smaller, which averages it.
    static let maxBufferSide = 32

    /// The mean luma of `rect` in `image`, from 0 (black) to 1 (white), using Rec. 709 weights on
    /// the sRGB values. `rect` is in image pixels with the origin at the top left, as for
    /// `CGImage.cropping(to:)`; the part outside the image is ignored, and nil means nothing was
    /// left. The crop is drawn into an 8-bit RGBA buffer of at most 32 by 32 pixels, so a call costs
    /// the same at any display scale.
    static func mean(of image: CGImage, in rect: CGRect) -> Double? {
        let visible = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !visible.isNull, !visible.isEmpty, let cropped = image.cropping(to: visible),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = min(cropped.width, maxBufferSide)
        let height = min(cropped.height, maxBufferSide)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return total / Double(width * height) / 255
    }
}

/// The colour of the crosshair and the selection border for what is under the cursor.
nonisolated enum CrosshairStyle: Equatable, Sendable {
    /// Black at 0.8 alpha, on a light background.
    case dark
    /// White at 0.8 alpha, on a dark background.
    case light
    /// White with a one-pixel black edge beneath, readable on anything. Used until the snapshot
    /// arrives, and when the cursor is outside it.
    case outlined

    init(luminance: Double?) {
        guard let luminance else {
            self = .outlined
            return
        }
        self = luminance > 0.5 ? .dark : .light
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 179 tests in 26 suites passed`.

- [ ] **Step 5: Draw with the sampled colour**

In `TidyShot/Selection/SelectionView.swift`:

Replace:
```swift
    /// Screenshot of this view's display, in pixels, used by the loupe.
    var snapshot: CGImage? {
        didSet { needsDisplay = true }
    }
    var snapshotScale: CGFloat = 2
```
with:
```swift
    /// Screenshot of this view's display, in pixels, used by the loupe and to pick the crosshair
    /// colour.
    var snapshot: CGImage? {
        didSet {
            crosshairStyle = style(at: cursor)
            needsDisplay = true
        }
    }
    var snapshotScale: CGFloat = 2
    /// Recomputed when the cursor moves or the snapshot arrives, never while drawing.
    private var crosshairStyle: CrosshairStyle = .outlined
```

Replace:
```swift
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        needsDisplay = true
```
with:
```swift
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        crosshairStyle = style(at: point)
        needsDisplay = true
```

Replace:
```swift
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        dragRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
```
with:
```swift
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        crosshairStyle = style(at: point)
        dragRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
```

Replace:
```swift
        if let completedRect {
            punchHole(completedRect)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: completedRect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            return
        }
```
with:
```swift
        if let completedRect {
            punchHole(completedRect)
            stroke(NSBezierPath(rect: completedRect.insetBy(dx: 0.5, dy: 0.5)))
            return
        }
```

Replace:
```swift
        if isDragging, let rect = dragRect {
            punchHole(rect)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            drawSizeLabel(for: rect)
```
with:
```swift
        if isDragging, let rect = dragRect {
            punchHole(rect)
            stroke(NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)))
            drawSizeLabel(for: rect)
```

Replace:
```swift
    private func drawCrosshair(at point: CGPoint) {
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: bounds.minX, y: point.y + 0.5))
        path.line(to: CGPoint(x: bounds.maxX, y: point.y + 0.5))
        path.move(to: CGPoint(x: point.x + 0.5, y: bounds.minY))
        path.line(to: CGPoint(x: point.x + 0.5, y: bounds.maxY))
        path.stroke()
    }
```
with:
```swift
    private func drawCrosshair(at point: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.minX, y: point.y + 0.5))
        path.line(to: CGPoint(x: bounds.maxX, y: point.y + 0.5))
        path.move(to: CGPoint(x: point.x + 0.5, y: bounds.minY))
        path.line(to: CGPoint(x: point.x + 0.5, y: bounds.maxY))
        stroke(path)
    }

    /// Strokes a 1 pt line in the current `crosshairStyle`: black on light backgrounds, white on
    /// dark ones, and before the snapshot arrives white over a line one pixel wider on each side
    /// in black.
    private func stroke(_ path: NSBezierPath) {
        switch crosshairStyle {
        case .dark:
            NSColor.black.withAlphaComponent(0.8).setStroke()
        case .light:
            NSColor.white.withAlphaComponent(0.8).setStroke()
        case .outlined:
            NSColor.black.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 1 + 2 / (window?.backingScaleFactor ?? 2)
            path.stroke()
            NSColor.white.setStroke()
        }
        path.lineWidth = 1
        path.stroke()
    }

    /// The style for the snapshot under `point` (view coordinates): the mean luminance of a
    /// `Luminance.sampleSide` point square around it. `.outlined` without a snapshot or a cursor.
    private func style(at point: CGPoint?) -> CrosshairStyle {
        guard let point, let snapshot else { return .outlined }
        // Snapshot pixels run top to bottom; the view's y runs bottom to top.
        let side = Luminance.sampleSide * snapshotScale
        let centre = CGPoint(x: point.x * snapshotScale, y: (bounds.height - point.y) * snapshotScale)
        let rect = CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        return CrosshairStyle(luminance: Luminance.mean(of: snapshot, in: rect))
    }
```

- [ ] **Step 6: Build, run the tests, and check by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 179 tests in 26 suites passed`.

Then:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Open a white page (a new TextEdit document) beside a dark window (Terminal), press `⌃⇧4` and move the cursor between them. Expected: for the first moment (before the snapshot) the crosshair is white with a thin dark edge; then it is black over the white page and white over the dark window; while dragging, the rectangle border follows the same colour as the area under the cursor. Escape cancels.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Selection/Luminance.swift TidyShotTests/LuminanceTests.swift TidyShot/Selection/SelectionView.swift
git commit -m "feat: crosshair and selection border adapt to the background"
```

---

### Task 6: AppKit menu bar item (`NSStatusItem` and `NSMenu`)

**Files:**
- Create: `TidyShot/App/StatusMenuController.swift`
- Create: `TidyShot/App/SettingsOpener.swift`
- Modify: `TidyShot/App/TidyShotApp.swift` (full replacement)
- Modify: `TidyShot/App/AppDelegate.swift` (one edit)
- Delete: `TidyShot/App/MenuContent.swift`

**Interfaces:**
- Consumes: `AppCoordinator.permissionGranted`, `isCapturing`, `isUploading`, `lastCaptureURL`, `history.failedRecords`, `captureArea()`, `captureWindow()`, `captureFullscreen()`, `showPermissionWindow()`, `showGallery()`, `retryFailedUploads()`, `revealLastCapture()` (Phases 1 to 3); `KeyboardShortcuts.getShortcut(for:)` and the three `KeyboardShortcuts.Name`s in `Shortcuts.swift`.
- Produces:
  - `final class StatusMenuController: NSObject, NSMenuDelegate` with `init(coordinator: AppCoordinator)`. It owns the `NSStatusItem` and its `NSMenu` (rebuilt in `menuNeedsUpdate(_:)`), switches the icon between `camera.viewfinder` and `arrow.up.circle` by observing `coordinator.isUploading`, and keeps a private `menu: NSMenu` that Task 7 uses to close the menu.
  - `final class SettingsOpener` with `install(in view: NSView?)` and `open()`.
  - `TidyShotApp` declares only `Settings { SettingsView() }`; `AppDelegate` creates the `StatusMenuController` after `AppCoordinator.shared.start()`, never in the test host.
  - The menu reads exactly as before: optional permission item, the three captures with their shortcuts in the title, Recent Captures… (still the gallery in this task), Retry Failed Uploads when there are failures, Reveal Last Capture, Settings… (⌘,), Quit TidyShot (⌘Q).

- [ ] **Step 1: Write the Settings opener**

How to open the SwiftUI `Settings` scene from AppKit was checked on this machine (macOS 27, SDK 27.0) with a scratch app that has only a `Settings` scene and `LSUIElement`: `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` returned `true` and opened no window, while SwiftUI's `openSettings` environment action, read by a view in a zero-size `NSHostingView` inside the status item's button and called later from AppKit, opened the window, and opened it again after it was closed. A hidden `MenuBarExtra` is not needed.

`TidyShot/App/SettingsOpener.swift`:
```swift
import AppKit
import SwiftUI

/// Opens the SwiftUI `Settings` scene from AppKit code.
///
/// The `showSettingsWindow:` action that used to do this no longer opens the window (macOS 27:
/// `NSApp.sendAction` returns true and nothing appears). SwiftUI's `openSettings` environment
/// action does, but only a SwiftUI view can read it, so `install(in:)` adds a zero-size
/// `NSHostingView` to a view that is always on screen (the status item's button); its view reads
/// the action when it appears and hands it over.
final class SettingsOpener {
    private var action: OpenSettingsAction?

    func install(in view: NSView?) {
        let reader = NSHostingView(rootView: SettingsActionReader { [weak self] action in
            self?.action = action
        })
        reader.frame = .zero
        view?.addSubview(reader)
    }

    /// Activates the app first: a menu bar agent is not active when its menu is used, and the
    /// window would open behind the frontmost app.
    func open() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let action else {
            NSLog("Settings cannot be opened yet: the openSettings action has not been read")
            return
        }
        action()
    }
}

/// Reads `openSettings` from the environment once it is on screen. No work in `body`.
private struct SettingsActionReader: View {
    @Environment(\.openSettings) private var openSettings
    let receive: (OpenSettingsAction) -> Void

    var body: some View {
        Color.clear
            .onAppear { receive(openSettings) }
    }
}
```

- [ ] **Step 2: Write the status menu**

`TidyShot/App/StatusMenuController.swift`:
```swift
import AppKit
import KeyboardShortcuts
import Observation

/// The menu bar item: an AppKit `NSStatusItem` with an `NSMenu`, because Recent Captures must be
/// a submenu that opens on hover and holds rows with custom views, which the SwiftUI menu bar scene
/// cannot do.
/// The menu is rebuilt each time it opens, so the shortcut titles, the permission item and Retry
/// Failed Uploads are current. Using the menu never activates the app; only the alerts and
/// windows it leads to do (Settings, the permission window, the delete confirmation).
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let coordinator: AppCoordinator
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let settingsOpener = SettingsOpener()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu(title: "TidyShot")
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        settingsOpener.install(in: statusItem.button)
        updateIcon()
    }

    /// `camera.viewfinder`, or `arrow.up.circle` while an upload runs. Observation calls `onChange`
    /// once per registration (before the value changes), so the update is scheduled and registers
    /// again; the main queue also runs while a menu is tracking, so the icon changes with the menu open.
    private func updateIcon() {
        let uploading = withObservationTracking {
            coordinator.isUploading
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
        let image = NSImage(systemSymbolName: uploading ? "arrow.up.circle" : "camera.viewfinder",
                            accessibilityDescription: uploading ? "TidyShot, uploading" : "TidyShot")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        if !coordinator.permissionGranted {
            menu.addItem(item("Screen Recording permission needed…", #selector(showPermission)))
            menu.addItem(.separator())
        }
        menu.addItem(captureItem("Capture Area", .captureArea, #selector(captureArea)))
        menu.addItem(captureItem("Capture Window", .captureWindow, #selector(captureWindow)))
        menu.addItem(captureItem("Capture Fullscreen", .captureFullscreen, #selector(captureFullscreen)))
        menu.addItem(.separator())
        menu.addItem(item("Recent Captures…", #selector(showRecentCaptures)))
        if !coordinator.history.failedRecords.isEmpty {
            menu.addItem(item("Retry Failed Uploads", #selector(retryFailedUploads)))
        }
        let reveal = item("Reveal Last Capture", #selector(revealLastCapture))
        reveal.isEnabled = coordinator.lastCaptureURL != nil
        menu.addItem(reveal)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit TidyShot", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    /// "Capture Area  ⌃⇧4": the shortcut is part of the title, as the SwiftUI menu showed it, and
    /// is not a key equivalent, which would fire the capture a second time through the global
    /// hotkey that the menu buffers while it is open.
    private func captureItem(_ title: String, _ name: KeyboardShortcuts.Name, _ action: Selector) -> NSMenuItem {
        let shortcut = KeyboardShortcuts.getShortcut(for: name)
        let menuItem = item(shortcut.map { "\(title)  \($0)" } ?? title, action)
        menuItem.isEnabled = !coordinator.isCapturing
        return menuItem
    }

    // MARK: Actions (AppKit calls these after the menu has closed)

    @objc private func showPermission() { coordinator.showPermissionWindow() }
    @objc private func captureArea() { Task { await coordinator.captureArea() } }
    @objc private func captureWindow() { Task { await coordinator.captureWindow() } }
    @objc private func captureFullscreen() { Task { await coordinator.captureFullscreen() } }
    @objc private func showRecentCaptures() { coordinator.showGallery() }
    @objc private func retryFailedUploads() { coordinator.retryFailedUploads() }
    @objc private func revealLastCapture() { coordinator.revealLastCapture() }
    @objc private func openSettings() { settingsOpener.open() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
```

- [ ] **Step 3: Hand the menu bar to AppKit**

`TidyShot/App/TidyShotApp.swift`:
```swift
import SwiftUI

/// The SwiftUI side of the app is the Settings scene only. The menu bar item is AppKit
/// (`StatusMenuController`, created by `AppDelegate`).
@main
struct TidyShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
```

In `TidyShot/App/AppDelegate.swift`:

Replace:
```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppCoordinator.shared.start()
    }
```
with:
```swift
    /// The menu bar item, kept for the life of the app.
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppCoordinator.shared.start()
        statusMenu = StatusMenuController(coordinator: .shared)
    }
```

Then delete the SwiftUI menu:
```bash
git rm TidyShot/App/MenuContent.swift
```

- [ ] **Step 4: Build and run the tests**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 179 tests in 26 suites passed`.

- [ ] **Step 5: Check the menu by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected: exactly one TidyShot icon in the menu bar (the viewfinder); its menu lists Capture Area `⌃⇧4`, Capture Window `⌃⇧2`, Capture Fullscreen `⌃⇧3`, Recent Captures…, Retry Failed Uploads (only with a failed upload in history), Reveal Last Capture (disabled before the first save), Settings…, Quit TidyShot. Opening the menu leaves the frontmost app active (its name stays in the menu bar). Settings… opens the Settings window in front, also a second time after closing it; ⌘, while the menu is open does the same. During an upload of a fullscreen capture the icon is `arrow.up.circle` and turns back afterwards. Revoke Screen Recording in System Settings and relaunch: the first item is "Screen Recording permission needed…" and opens the permission window. Each capture item starts its capture; Recent Captures… opens the gallery; Quit quits.

- [ ] **Step 6: Commit**

```bash
git add TidyShot/App/StatusMenuController.swift TidyShot/App/SettingsOpener.swift TidyShot/App/TidyShotApp.swift TidyShot/App/AppDelegate.swift
git commit -m "feat: menu bar item on NSStatusItem with an AppKit menu"
```

---

### Task 7: Recent Captures submenu with custom rows; gallery window removed (TDD for the row text)

**Files:**
- Create: `TidyShot/RecentCaptures/RecentCaptureFormatting.swift`
- Create: `TidyShot/RecentCaptures/RecentCaptureRow.swift`
- Create: `TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift`
- Create: `TidyShot/RecentCaptures/RecentCapturesMenu.swift`
- Create: `TidyShotTests/RecentCaptureFormattingTests.swift`
- Move: `TidyShot/Gallery/ThumbnailProvider.swift` to `TidyShot/RecentCaptures/ThumbnailProvider.swift` (one comment edit)
- Delete: `TidyShot/Gallery/GalleryModel.swift`, `TidyShot/Gallery/GalleryView.swift`, `TidyShot/Gallery/GalleryWindowController.swift` (the `Gallery` folder goes with them)
- Modify: `TidyShot/App/AppCoordinator.swift`, `TidyShot/App/StatusMenuController.swift` (edits below)
- Modify (comments only): `TidyShot/Settings/AppSettings.swift`, `TidyShot/Output/ThumbnailMaker.swift`, `TidyShot/Output/SaveLocation.swift`, `TidyShot/History/CaptureRecord.swift`

**Interfaces:**
- Consumes: `ThumbnailProvider.thumbnail(for:)` (unchanged, and its tests stay), `AppCoordinator.copyLinkOrFile(recordID:)`, `copyImage(recordID:)` (Task 4), `deleteCapture(recordID:)` (Task 3), `StatusMenuController.menu` (Task 6).
- Produces:
  - `nonisolated enum RecentCaptureFormatting { static func name(for: CaptureRecord) -> String; static func detail(for: CaptureRecord, now: Date, locale: Locale = .current) -> String; static func canCopyLink(_: CaptureRecord) -> Bool; static func canCopyImage(_: CaptureRecord) -> Bool }`.
  - `struct RecentCaptureActions { var copyLinkOrFile, copyLink, copyImage, delete: (UUID) -> Void }`, `@Observable final class RecentCaptureRowState { var isHighlighted: Bool }`, `struct RecentCaptureRow: View` with `static let size` (360 by 52), `thumbnailSize` (56 by 42), `horizontalPadding` (14) and `thumbnailFrame`.
  - `final class RecentCaptureMenuItemView: NSView` with `init(record:now:provider:actions:)` and `let recordID: UUID` (Task 8 replaces this file to add the thumbnail hover).
  - `final class RecentCapturesMenu: NSObject` with `static let limit = 15`, `let item: NSMenuItem` (titled "Recent Captures", its submenu is `menu`), `let menu: NSMenu`, `init(coordinator: AppCoordinator, closeMenus: @escaping () -> Void)`, `rebuild()` (Task 8 replaces this file to add the preview).
  - `AppCoordinator.copyLink(recordID: UUID)`; `AppCoordinator.thumbnailProvider` becomes readable outside the class (`private(set)`); `showGallery()` and the `gallery` property are gone.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/RecentCaptureFormattingTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct RecentCaptureFormattingTests {
    /// 2026-10-19T12:00:00Z
    let now = Date(timeIntervalSince1970: 1_792_411_200)
    let english = Locale(identifier: "en_US")
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap", usePathStyle: false)

    func record(_ state: CaptureRecord.UploadState, file: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                secondsAgo: TimeInterval = 120, location: ObjectLocation? = nil, appName: String? = nil) -> CaptureRecord {
        CaptureRecord(timestamp: now.addingTimeInterval(-secondsAgo), fileURL: file, pixelWidth: 10, pixelHeight: 10,
                      appName: appName, uploadState: state, objectLocation: location)
    }

    @Test func nameIsTheObjectOrTheFileName() {
        let url = URL(string: "https://snap.tky.io/shots/2026/10/aB3dE9.png")!
        #expect(RecentCaptureFormatting.name(for: record(.uploaded(url: url, key: "shots/2026/10/aB3dE9.png"))) == "aB3dE9.png")
        #expect(RecentCaptureFormatting.name(for: record(.none)) == "Shot.png")
        #expect(RecentCaptureFormatting.name(for: record(.failed(message: "x"), file: nil, appName: "Safari")) == "Safari")
        #expect(RecentCaptureFormatting.name(for: record(.failed(message: "x"), file: nil)) == "Capture")
    }

    @Test func detailIsTheRelativeTimeAndAnUnsettledState() {
        #expect(RecentCaptureFormatting.detail(for: record(.none), now: now, locale: english) == "2 minutes ago")
        #expect(RecentCaptureFormatting.detail(for: record(.uploading(fraction: 0.5)), now: now, locale: english)
                == "2 minutes ago · Uploading")
        #expect(RecentCaptureFormatting.detail(for: record(.failed(message: "offline"), secondsAgo: 86_400), now: now, locale: english)
                == "yesterday · Upload failed")
        #expect(RecentCaptureFormatting.detail(for: record(.none, secondsAgo: 0), now: now, locale: english) == "now")
    }

    @Test func buttonsFollowWhatTheCaptureHas() {
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        let uploadOnly = record(.uploaded(url: url, key: "aB3dE9.png"), file: nil, location: location)
        #expect(RecentCaptureFormatting.canCopyLink(uploadOnly))
        #expect(RecentCaptureFormatting.canCopyImage(uploadOnly))

        let saved = record(.none)
        #expect(!RecentCaptureFormatting.canCopyLink(saved))
        #expect(RecentCaptureFormatting.canCopyImage(saved))

        // Uploaded before Phase 3 (no location) and its file deleted: nothing to download from.
        let phase2WithoutFile = record(.uploaded(url: url, key: "aB3dE9.png"), file: nil)
        #expect(RecentCaptureFormatting.canCopyLink(phase2WithoutFile))
        #expect(!RecentCaptureFormatting.canCopyImage(phase2WithoutFile))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `cannot find 'RecentCaptureFormatting' in scope`.

- [ ] **Step 3: Write the row text**

`TidyShot/RecentCaptures/RecentCaptureFormatting.swift`:
```swift
import Foundation

/// The text and button states of a Recent Captures row, worked out before the row is built so
/// that its SwiftUI `body` only lays them out.
nonisolated enum RecentCaptureFormatting {
    /// `aSIS7x.png`: the last part of the public URL once uploaded, otherwise the local file's
    /// name. A record from before Phase 3.1 with neither shows its app name.
    static func name(for record: CaptureRecord) -> String {
        record.uploadedURL?.lastPathComponent ?? record.fileURL?.lastPathComponent ?? record.appName ?? "Capture"
    }

    /// "2 minutes ago", with the upload state while it is not settled: "2 minutes ago · Uploading",
    /// "yesterday · Upload failed".
    static func detail(for record: CaptureRecord, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let time = formatter.localizedString(for: record.timestamp, relativeTo: now)
        switch record.uploadState {
        case .uploading: return "\(time) · Uploading"
        case .failed: return "\(time) · Upload failed"
        case .none, .uploaded: return time
        }
    }

    /// Copy URL needs an uploaded object.
    static func canCopyLink(_ record: CaptureRecord) -> Bool {
        record.uploadedURL != nil
    }

    /// Copy Image needs a local file, or an uploaded object whose bucket is known (signed GET).
    static func canCopyImage(_ record: CaptureRecord) -> Bool {
        record.hasLocalFile || (record.uploadedKey != nil && record.objectLocation != nil)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 182 tests in 27 suites passed`.

- [ ] **Step 5: Write the row and its menu item view**

How the row behaves inside a menu was checked on this machine (macOS 27) with a scratch app and again in the test host with these files: a tracking area (`.mouseEnteredAndExited`, `.activeAlways`) on the view set as `NSMenuItem.view` receives `mouseEntered` and `mouseExited` while the menu tracks, as the cursor moves; clicks inside the item's `NSHostingView` reach a SwiftUI `Button` with `.buttonStyle(.plain)` filling the left of the row and the `.borderless` icon buttons beside it, each firing only its own action; and a block given to `RunLoop.main.perform(inModes: [.default])` from inside the menu runs only after `cancelTracking()` has ended the tracking, which is what `afterMenusClose` relies on.

`TidyShot/RecentCaptures/RecentCaptureRow.swift`:
```swift
import SwiftUI

/// What a Recent Captures row's buttons do. `RecentCapturesMenu` makes each one close the menu first.
struct RecentCaptureActions {
    /// Clicking the row: the URL, or the file when the capture was never uploaded.
    var copyLinkOrFile: (UUID) -> Void
    var copyLink: (UUID) -> Void
    var copyImage: (UUID) -> Void
    /// The overlay's delete: one confirmation, then storage, file, thumbnail and record.
    var delete: (UUID) -> Void
}

/// Hover state of one row, set from AppKit by `RecentCaptureMenuItemView`.
@Observable
final class RecentCaptureRowState {
    var isHighlighted = false
}

/// One row of the Recent Captures submenu: thumbnail, name, relative time, and Copy URL, Copy
/// Image and Delete buttons. Every string and flag is worked out before the row is built, and the
/// thumbnail loads in `.task`, so `body` does no work.
struct RecentCaptureRow: View {
    static let size = CGSize(width: 360, height: 52)
    static let thumbnailSize = CGSize(width: 56, height: 42)
    static let horizontalPadding: CGFloat = 14
    /// Where the thumbnail sits, in the item view's coordinates. The row is symmetric top to
    /// bottom, so AppKit's bottom-left origin gives the same rect.
    static let thumbnailFrame = CGRect(x: horizontalPadding, y: (size.height - thumbnailSize.height) / 2,
                                       width: thumbnailSize.width, height: thumbnailSize.height)

    let record: CaptureRecord
    let name: String
    let detail: String
    let canCopyLink: Bool
    let canCopyImage: Bool
    let state: RecentCaptureRowState
    let provider: ThumbnailProvider
    let actions: RecentCaptureActions
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 4) {
            Button { actions.copyLinkOrFile(record.id) } label: {
                HStack(spacing: 10) {
                    thumbnailView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(detail)")
            .accessibilityHint(canCopyLink ? "Copies the link" : "Copies the file")
            iconButton("link", label: "Copy URL", enabled: canCopyLink) { actions.copyLink(record.id) }
            iconButton("photo.on.rectangle", label: "Copy Image", enabled: canCopyImage) { actions.copyImage(record.id) }
            iconButton("trash", label: "Delete…", enabled: true) { actions.delete(record.id) }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if state.isHighlighted {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .padding(.horizontal, 5)
            }
        }
        .task(id: record.thumbnailFileName) {
            thumbnail = await provider.thumbnail(for: record)
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func iconButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
```

`TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift`:
```swift
import AppKit
import SwiftUI

/// One Recent Captures menu item: the SwiftUI `RecentCaptureRow` in an `NSHostingView`, plus an
/// AppKit tracking area over the row for its highlight (a menu does not highlight custom views).
/// Tracking areas in a menu item's view receive `mouseEntered` and `mouseExited` while the menu
/// tracks; they never take clicks, which go to the row's buttons.
final class RecentCaptureMenuItemView: NSView {
    let recordID: UUID
    private let state = RecentCaptureRowState()
    private var rowArea: NSTrackingArea?

    init(record: CaptureRecord, now: Date, provider: ThumbnailProvider, actions: RecentCaptureActions) {
        recordID = record.id
        super.init(frame: CGRect(origin: .zero, size: RecentCaptureRow.size))
        let row = RecentCaptureRow(record: record,
                                   name: RecentCaptureFormatting.name(for: record),
                                   detail: RecentCaptureFormatting.detail(for: record, now: now),
                                   canCopyLink: RecentCaptureFormatting.canCopyLink(record),
                                   canCopyImage: RecentCaptureFormatting.canCopyImage(record),
                                   state: state, provider: provider, actions: actions)
        let host = NSHostingView(rootView: row)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateTrackingAreas() {
        if let rowArea { removeTrackingArea(rowArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        rowArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        state.isHighlighted = true
    }

    override func mouseExited(with event: NSEvent) {
        state.isHighlighted = false
    }
}
```

- [ ] **Step 6: Write the submenu**

`TidyShot/RecentCaptures/RecentCapturesMenu.swift`:
```swift
import AppKit

/// The Recent Captures submenu: the newest captures, up to 15, as custom rows. A row's buttons
/// close the whole menu and act once menu tracking has ended, so the delete alert never runs
/// inside the menu's tracking loop.
final class RecentCapturesMenu: NSObject {
    static let limit = 15

    /// The status menu's "Recent Captures" item; its submenu is `menu`. Created once and added
    /// again on every rebuild, because a menu can be the submenu of only one item.
    let item = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Recent Captures")
    private let coordinator: AppCoordinator
    /// Cancels tracking of the status menu, which closes this submenu too.
    private let closeMenus: () -> Void

    init(coordinator: AppCoordinator, closeMenus: @escaping () -> Void) {
        self.coordinator = coordinator
        self.closeMenus = closeMenus
        super.init()
        menu.autoenablesItems = false
        item.submenu = menu
    }

    /// Fills the submenu from the history; called by `StatusMenuController` each time the status
    /// menu opens. Rows show their records as they were at that moment.
    func rebuild() {
        menu.removeAllItems()
        let records = coordinator.history.records.prefix(Self.limit)
        guard !records.isEmpty else {
            let empty = NSMenuItem(title: "No captures yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        let now = Date()
        let actions = makeActions()
        for record in records {
            let row = NSMenuItem()
            row.view = RecentCaptureMenuItemView(record: record, now: now, provider: coordinator.thumbnailProvider,
                                                 actions: actions)
            menu.addItem(row)
        }
    }

    private func makeActions() -> RecentCaptureActions {
        RecentCaptureActions(
            copyLinkOrFile: { [weak self] id in self?.afterMenusClose { $0.copyLinkOrFile(recordID: id) } },
            copyLink: { [weak self] id in self?.afterMenusClose { $0.copyLink(recordID: id) } },
            copyImage: { [weak self] id in self?.afterMenusClose { coordinator in Task { await coordinator.copyImage(recordID: id) } } },
            delete: { [weak self] id in self?.afterMenusClose { coordinator in Task { await coordinator.deleteCapture(recordID: id) } } })
    }

    /// Closes the menus, then runs `work` when the run loop is back in its default mode, that is,
    /// after menu tracking has ended (`perform(inModes:)` does not run in the menu's
    /// event-tracking mode).
    private func afterMenusClose(_ work: @escaping @MainActor (AppCoordinator) -> Void) {
        closeMenus()
        let coordinator = coordinator
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { work(coordinator) }
        }
    }
}
```

- [ ] **Step 7: Remove the gallery and move the thumbnail provider**

```bash
mkdir -p TidyShot/RecentCaptures
git mv TidyShot/Gallery/ThumbnailProvider.swift TidyShot/RecentCaptures/ThumbnailProvider.swift
git rm TidyShot/Gallery/GalleryModel.swift TidyShot/Gallery/GalleryView.swift TidyShot/Gallery/GalleryWindowController.swift
```

In `TidyShot/RecentCaptures/ThumbnailProvider.swift`:

Replace:
```swift
/// Thumbnails and larger previews for the gallery, through async methods that the gallery calls
/// from `.task` modifiers, never from a view body. Thumbnails come from the `thumbnails` folder;
```
with:
```swift
/// Thumbnails and larger previews for Recent Captures, through async methods that its rows and
/// hover preview call from tasks, never from a view body. Thumbnails come from the `thumbnails` folder;
```

In `TidyShot/App/AppCoordinator.swift`:

Replace:
```swift
    @ObservationIgnored private lazy var thumbnailProvider = ThumbnailProvider(
```
with:
```swift
    /// Thumbnails and previews for Recent Captures.
    @ObservationIgnored private(set) lazy var thumbnailProvider = ThumbnailProvider(
```

Replace:
```swift
    @ObservationIgnored private lazy var gallery = GalleryWindowController(
        model: GalleryModel(history: history, provider: thumbnailProvider),
        actions: GalleryActions(
            copy: { [weak self] id in self?.copyLinkOrFile(recordID: id) },
            retry: { [weak self] id in self?.retryUpload(recordID: id) },
            reveal: { [weak self] id in self?.reveal(recordID: id) },
            delete: { [weak self] id in Task { await self?.deleteCapture(recordID: id) } }))
    /// The queue new uploads go to, built from the destination of the first upload after launch
```
with:
```swift
    /// The queue new uploads go to, built from the destination of the first upload after launch
```

Replace:
```swift
    func showPermissionWindow() {
        permissionWindow.show()
    }

    /// Opens (or brings forward) the Recent Captures gallery.
    func showGallery() {
        gallery.show()
    }
```
with:
```swift
    func showPermissionWindow() {
        permissionWindow.show()
    }
```

Replace:
```swift
    /// its file name on the record when that finishes. Until then the gallery makes one from the
    /// file itself; a failure is logged and the gallery falls back the same way. If the record was
```
with:
```swift
    /// its file name on the record when that finishes. Until then `ThumbnailProvider` makes one
    /// from the file itself; a failure is logged and it falls back the same way. If the record was
```

Replace:
```swift
    /// Copy Image: the PNG and TIFF on the clipboard, from the local file when it can be read;
```
with:
```swift
    /// Copy URL: the public URL of an uploaded capture. A capture that was never uploaded has none,
    /// and its row's button is disabled.
    func copyLink(recordID: UUID) {
        guard let url = history.record(id: recordID)?.uploadedURL else { return }
        Pasteboard.copy(url: url)
    }

    /// Copy Image: the PNG and TIFF on the clipboard, from the local file when it can be read;
```

In `TidyShot/App/StatusMenuController.swift`:

Replace:
```swift
    private let settingsOpener = SettingsOpener()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu(title: "TidyShot")
        super.init()
```
with:
```swift
    private let settingsOpener = SettingsOpener()
    private let recentCaptures: RecentCapturesMenu

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu(title: "TidyShot")
        self.menu = menu
        // Row buttons close the status menu, which closes the submenu with it.
        recentCaptures = RecentCapturesMenu(coordinator: coordinator, closeMenus: { [weak menu] in menu?.cancelTracking() })
        super.init()
```

Replace:
```swift
        menu.addItem(item("Recent Captures…", #selector(showRecentCaptures)))
```
with:
```swift
        recentCaptures.rebuild()
        menu.addItem(recentCaptures.item)
```

Replace:
```swift
    @objc private func captureFullscreen() { Task { await coordinator.captureFullscreen() } }
    @objc private func showRecentCaptures() { coordinator.showGallery() }
```
with:
```swift
    @objc private func captureFullscreen() { Task { await coordinator.captureFullscreen() } }
```

In `TidyShot/Settings/AppSettings.swift`:

Replace:
```swift
    /// once the upload succeeds. No save folder is needed; the gallery keeps a thumbnail.
```
with:
```swift
    /// once the upload succeeds. No save folder is needed; Recent Captures keeps a thumbnail.
```

In `TidyShot/Output/ThumbnailMaker.swift`:

Replace:
```swift
    /// For the gallery's hover preview, built from the local file when there is one.
```
with:
```swift
    /// For the Recent Captures hover preview, built from the local file when there is one.
```

Replace:
```swift
    /// thumbnails existed and for the gallery's larger preview; the bytes come from
```
with:
```swift
    /// thumbnails existed and for the larger hover preview; the bytes come from
```

In `TidyShot/Output/SaveLocation.swift`:

Replace:
```swift
    /// Touches no instance state, so it can run off the main actor (the gallery's loads).
```
with:
```swift
    /// Touches no instance state, so it can run off the main actor (thumbnail and preview loads).
```

In `TidyShot/History/CaptureRecord.swift`:

Replace:
```swift
    /// before thumbnails existed; the gallery generates one from the local file when it can.
```
with:
```swift
    /// before thumbnails existed; `ThumbnailProvider` generates one from the local file when it can.
```

- [ ] **Step 8: Build and run the tests**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 182 tests in 27 suites passed` (ThumbnailProviderTests keeps its 5 tests).

Then:
```bash
ls TidyShot/Gallery 2>&1; grep -rni "gallery" TidyShot
```
Expected: `ls: TidyShot/Gallery: No such file or directory` and no grep output.

- [ ] **Step 9: Check the submenu by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected: hovering "Recent Captures" opens the submenu without a click; it lists at most 15 captures, newest first, each with a thumbnail, its name (`aSIS7x.png` or the file name) and "2 minutes ago"; the row under the mouse is highlighted. Clicking a row of an uploaded capture closes the menu and puts the URL on the clipboard; a never-uploaded one puts the file there (paste in Finder makes a copy). The link button is greyed out for a never-uploaded capture and copies the URL otherwise; the photo button copies the image (paste in Notes shows it at point size); the trash button closes the menu and shows the "Delete this capture?" alert. With an empty history the submenu shows a greyed "No captures yet". The frontmost app stays active throughout, except while the alert is up.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/RecentCaptures TidyShotTests/RecentCaptureFormattingTests.swift TidyShot/App/AppCoordinator.swift TidyShot/App/StatusMenuController.swift TidyShot/Settings/AppSettings.swift TidyShot/Output/ThumbnailMaker.swift TidyShot/Output/SaveLocation.swift TidyShot/History/CaptureRecord.swift
git commit -m "feat: Recent Captures hover submenu with custom rows; remove the gallery window"
```

---

### Task 8: Full-size preview beside the submenu while a thumbnail is hovered (TDD for the placement)

**Files:**
- Create: `TidyShot/RecentCaptures/PreviewPlacement.swift`
- Create: `TidyShot/RecentCaptures/PreviewPanel.swift`
- Create: `TidyShotTests/PreviewPlacementTests.swift`
- Modify: `TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift` (full replacement)
- Modify: `TidyShot/RecentCaptures/RecentCapturesMenu.swift` (full replacement)
- Modify: `TidyShot/App/StatusMenuController.swift` (one edit)

**Interfaces:**
- Consumes: `ThumbnailProvider.preview(for:) async -> NSImage?` (up to 1200 px from the local file, falling back to the thumbnail), `RecentCaptureRow.thumbnailFrame`, `RecentCaptureMenuItemView.recordID` (Task 7).
- Produces:
  - `nonisolated enum PreviewPlacement { static let maxSize: CGSize; static let gap: CGFloat; static func fitted(_ imageSize: CGSize, in bounds: CGSize) -> CGSize; static func frame(imageSize: CGSize, menuFrame: CGRect, rowFrame: CGRect, visibleFrame: CGRect) -> CGRect }`.
  - `final class PreviewPanel: NSPanel` with `init()`, `show(_ image: NSImage, frame: CGRect)` and `hide()`: non-activating, `.popUpMenu` level, ignores the mouse.
  - `RecentCaptureMenuItemView.init(record:now:provider:actions:onThumbnailHover:)` with `onThumbnailHover: @escaping (RecentCaptureMenuItemView, Bool) -> Void`.
  - `RecentCapturesMenu` becomes the submenu's `NSMenuDelegate` and gains `hidePreview()`; `StatusMenuController.menuDidClose(_:)` calls it as well.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/PreviewPlacementTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct PreviewPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    /// Fits 560 by 373 exactly at half size.
    let image = CGSize(width: 1120, height: 746)

    @Test func fittedShrinksButNeverEnlarges() {
        #expect(PreviewPlacement.fitted(CGSize(width: 1200, height: 800), in: PreviewPlacement.maxSize) == CGSize(width: 560, height: 373))
        #expect(PreviewPlacement.fitted(CGSize(width: 200, height: 100), in: PreviewPlacement.maxSize) == CGSize(width: 200, height: 100))
        #expect(PreviewPlacement.fitted(.zero, in: PreviewPlacement.maxSize) == .zero)
    }

    @Test func sitsLeftOfTheSubmenuCentredOnTheRow() {
        let menu = CGRect(x: 1400, y: 300, width: 360, height: 600)
        let row = CGRect(x: 1400, y: 700, width: 360, height: 52)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: menu, rowFrame: row, visibleFrame: screen)
                == CGRect(x: 832, y: 539.5, width: 560, height: 373))
    }

    @Test func staysInsideTheScreen() {
        let menu = CGRect(x: 1400, y: 400, width: 360, height: 640)
        let topRow = CGRect(x: 1400, y: 1000, width: 360, height: 40)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: menu, rowFrame: topRow, visibleFrame: screen)
                == CGRect(x: 832, y: 669, width: 560, height: 373))
    }

    /// A submenu at the left edge of the screen has no room on its left, so the preview goes right;
    /// with little room on both sides it shrinks to the larger one.
    @Test func goesRightWhenTheLeftHasNoRoom() {
        let menu = CGRect(x: 20, y: 300, width: 360, height: 600)
        let row = CGRect(x: 20, y: 500, width: 360, height: 52)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: menu, rowFrame: row, visibleFrame: screen)
                == CGRect(x: 388, y: 339.5, width: 560, height: 373))

        let narrow = CGRect(x: 0, y: 0, width: 1000, height: 1050)
        let middle = CGRect(x: 300, y: 0, width: 360, height: 600)
        let middleRow = CGRect(x: 300, y: 300, width: 360, height: 52)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: middle, rowFrame: middleRow, visibleFrame: narrow)
                == CGRect(x: 668, y: 218, width: 324, height: 216))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `cannot find 'PreviewPlacement' in scope`.

- [ ] **Step 3: Write the placement**

`TidyShot/RecentCaptures/PreviewPlacement.swift`:
```swift
import CoreGraphics

/// Where the full-size preview goes beside the Recent Captures submenu. Pure, so it is tested
/// without windows. All rects are AppKit screen coordinates (origin bottom left).
nonisolated enum PreviewPlacement {
    /// The largest preview, in points.
    static let maxSize = CGSize(width: 560, height: 420)
    /// Space between the preview and the submenu, and between the preview and the screen edge.
    static let gap: CGFloat = 8

    /// `imageSize` scaled down to fit `bounds`, never up, rounded to whole points.
    static func fitted(_ imageSize: CGSize, in bounds: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(1, bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: (imageSize.width * scale).rounded(), height: (imageSize.height * scale).rounded())
    }

    /// The preview's frame: to the left of `menuFrame` (the submenu's window), unless the left side
    /// is too narrow for the whole preview and the right side is wider; vertically centred on
    /// `rowFrame` (the hovered row) and kept inside `visibleFrame`.
    static func frame(imageSize: CGSize, menuFrame: CGRect, rowFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let leftRoom = menuFrame.minX - gap - (visibleFrame.minX + gap)
        let rightRoom = visibleFrame.maxX - gap - (menuFrame.maxX + gap)
        let heightBound = min(maxSize.height, visibleFrame.height - 2 * gap)
        let wanted = fitted(imageSize, in: CGSize(width: maxSize.width, height: heightBound))
        let onLeft = leftRoom >= wanted.width || leftRoom >= rightRoom
        let room = max(0, onLeft ? leftRoom : rightRoom)
        let size = fitted(imageSize, in: CGSize(width: min(maxSize.width, room), height: heightBound))
        let x = onLeft ? menuFrame.minX - gap - size.width : menuFrame.maxX + gap
        let y = min(max(rowFrame.midY - size.height / 2, visibleFrame.minY + gap), visibleFrame.maxY - gap - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 186 tests in 28 suites passed`.

- [ ] **Step 5: Write the panel and the hover**

Whether a panel can appear while a menu is tracking was checked on this machine (macOS 27), first with a scratch app and then in the test host with this task's own `RecentCaptureMenuItemView`, `PreviewPanel` and `PreviewPlacement` inside a menu opened with `popUp(positioning:at:in:)`: the panel, ordered front with `orderFrontRegardless()` from a timer running in the menu's tracking mode, was the frontmost on-screen window in `CGWindowListCopyWindowInfo`, above the menu's window at the same layer (101); the item view's `window?.frame` was the menu window's frame; the thumbnail callback fired with true and false as the cursor moved onto and off the thumbnail; and `menuDidClose(_:)` fired on `cancelTracking()`. Two things that check caught are built in below: the panel is not an `isFloatingPanel` (setting it moves the level back to `.floating`, under the menu), and tracking areas follow the real cursor position, so the hover can only be checked by moving the mouse, not with synthetic events alone.

`TidyShot/RecentCaptures/PreviewPanel.swift`:
```swift
import AppKit

/// The full-size preview beside the Recent Captures submenu while a thumbnail is hovered. It is
/// non-activating and at `.popUpMenu`, the menus' own level, so ordering it front puts it above
/// the open menu without taking the menu's tracking or activating the app. It ignores the mouse,
/// so it never takes a hover or a click meant for the menu.
final class PreviewPanel: NSPanel {
    private let imageView = NSImageView()

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 200, height: 150),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        // Not a floating panel: `isFloatingPanel = true` would put the level back to `.floating`,
        // below the menu.
        level = .popUpMenu
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            imageView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
            imageView.topAnchor.constraint(equalTo: background.topAnchor, constant: 6),
            imageView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -6),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `image` in `frame` (screen coordinates, from `PreviewPlacement`).
    func show(_ image: NSImage, frame: CGRect) {
        imageView.image = image
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
        imageView.image = nil
    }
}
```

The menu item view gains the thumbnail tracking area and its callback. Replace the whole file:

`TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift`:
```swift
import AppKit
import SwiftUI

/// One Recent Captures menu item: the SwiftUI `RecentCaptureRow` in an `NSHostingView`, plus two
/// AppKit tracking areas, one over the row for its highlight (a menu does not highlight custom
/// views) and one over the thumbnail for the preview. Tracking areas in a menu item's view
/// receive `mouseEntered` and `mouseExited` while the menu tracks; they never take clicks, which
/// go to the row's buttons.
final class RecentCaptureMenuItemView: NSView {
    let recordID: UUID
    private let state = RecentCaptureRowState()
    /// Called with true when the mouse enters the thumbnail and false when it leaves.
    private let onThumbnailHover: (RecentCaptureMenuItemView, Bool) -> Void
    private var rowArea: NSTrackingArea?
    private var thumbnailArea: NSTrackingArea?

    init(record: CaptureRecord, now: Date, provider: ThumbnailProvider, actions: RecentCaptureActions,
         onThumbnailHover: @escaping (RecentCaptureMenuItemView, Bool) -> Void) {
        recordID = record.id
        self.onThumbnailHover = onThumbnailHover
        super.init(frame: CGRect(origin: .zero, size: RecentCaptureRow.size))
        let row = RecentCaptureRow(record: record,
                                   name: RecentCaptureFormatting.name(for: record),
                                   detail: RecentCaptureFormatting.detail(for: record, now: now),
                                   canCopyLink: RecentCaptureFormatting.canCopyLink(record),
                                   canCopyImage: RecentCaptureFormatting.canCopyImage(record),
                                   state: state, provider: provider, actions: actions)
        let host = NSHostingView(rootView: row)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateTrackingAreas() {
        for area in [rowArea, thumbnailArea].compactMap({ $0 }) {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let row = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        let thumbnail = NSTrackingArea(rect: RecentCaptureRow.thumbnailFrame, options: options, owner: self, userInfo: nil)
        addTrackingArea(row)
        addTrackingArea(thumbnail)
        rowArea = row
        thumbnailArea = thumbnail
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === thumbnailArea {
            onThumbnailHover(self, true)
        } else if event.trackingArea === rowArea {
            state.isHighlighted = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === thumbnailArea {
            onThumbnailHover(self, false)
        } else if event.trackingArea === rowArea {
            state.isHighlighted = false
        }
    }
}
```

The submenu gains the preview and becomes its menu's delegate. Replace the whole file:

`TidyShot/RecentCaptures/RecentCapturesMenu.swift`:
```swift
import AppKit

/// The Recent Captures submenu: the newest captures, up to 15, as custom rows, and the full-size
/// preview beside the submenu while a thumbnail is hovered. A row's buttons close the whole menu
/// and act once menu tracking has ended, so the delete alert never runs inside the menu's
/// tracking loop.
final class RecentCapturesMenu: NSObject, NSMenuDelegate {
    static let limit = 15

    /// The status menu's "Recent Captures" item; its submenu is `menu`. Created once and added
    /// again on every rebuild, because a menu can be the submenu of only one item.
    let item = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Recent Captures")
    private let coordinator: AppCoordinator
    /// Cancels tracking of the status menu, which closes this submenu too.
    private let closeMenus: () -> Void
    private let previewPanel = PreviewPanel()
    /// The record whose thumbnail is under the mouse. A preview that finishes loading after the
    /// mouse moved on is dropped.
    private var hoveredID: UUID?

    init(coordinator: AppCoordinator, closeMenus: @escaping () -> Void) {
        self.coordinator = coordinator
        self.closeMenus = closeMenus
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.submenu = menu
    }

    /// Fills the submenu from the history; called by `StatusMenuController` each time the status
    /// menu opens. Rows show their records as they were at that moment.
    func rebuild() {
        hidePreview()
        menu.removeAllItems()
        let records = coordinator.history.records.prefix(Self.limit)
        guard !records.isEmpty else {
            let empty = NSMenuItem(title: "No captures yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        let now = Date()
        let actions = makeActions()
        for record in records {
            let row = NSMenuItem()
            row.view = RecentCaptureMenuItemView(record: record, now: now, provider: coordinator.thumbnailProvider,
                                                 actions: actions, onThumbnailHover: { [weak self] view, inside in
                                                     self?.thumbnailHover(view, inside: inside)
                                                 })
            menu.addItem(row)
        }
    }

    /// Hides the preview; also called by `StatusMenuController` when the status menu closes.
    func hidePreview() {
        hoveredID = nil
        previewPanel.hide()
    }

    // MARK: NSMenuDelegate

    func menuDidClose(_ menu: NSMenu) {
        hidePreview()
    }

    // MARK: Preview

    /// Loads the preview (up to 1200 px, off the main thread, cached by `ThumbnailProvider`) and
    /// shows it beside the submenu, level with the hovered row. The row view's window is the
    /// submenu's window, so its frame says where the submenu is on screen.
    private func thumbnailHover(_ view: RecentCaptureMenuItemView, inside: Bool) {
        guard inside else {
            if hoveredID == view.recordID { hidePreview() }
            return
        }
        guard let record = coordinator.history.record(id: view.recordID) else { return }
        hoveredID = record.id
        let provider = coordinator.thumbnailProvider
        Task { [weak self, weak view] in
            let image = await provider.preview(for: record)
            guard let self, let view, let image, self.hoveredID == record.id,
                  let menuWindow = view.window, let screen = menuWindow.screen ?? NSScreen.main else { return }
            let rowFrame = menuWindow.convertToScreen(view.convert(view.bounds, to: nil))
            let frame = PreviewPlacement.frame(imageSize: image.size, menuFrame: menuWindow.frame,
                                               rowFrame: rowFrame, visibleFrame: screen.visibleFrame)
            self.previewPanel.show(image, frame: frame)
        }
    }

    // MARK: Actions

    private func makeActions() -> RecentCaptureActions {
        RecentCaptureActions(
            copyLinkOrFile: { [weak self] id in self?.afterMenusClose { $0.copyLinkOrFile(recordID: id) } },
            copyLink: { [weak self] id in self?.afterMenusClose { $0.copyLink(recordID: id) } },
            copyImage: { [weak self] id in self?.afterMenusClose { coordinator in Task { await coordinator.copyImage(recordID: id) } } },
            delete: { [weak self] id in self?.afterMenusClose { coordinator in Task { await coordinator.deleteCapture(recordID: id) } } })
    }

    /// Closes the menus, then runs `work` when the run loop is back in its default mode, that is,
    /// after menu tracking has ended (`perform(inModes:)` does not run in the menu's
    /// event-tracking mode).
    private func afterMenusClose(_ work: @escaping @MainActor (AppCoordinator) -> Void) {
        hidePreview()
        closeMenus()
        let coordinator = coordinator
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { work(coordinator) }
        }
    }
}
```

In `TidyShot/App/StatusMenuController.swift`:

Replace:
```swift
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuild()
    }
```
with:
```swift
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuild()
    }

    /// The submenu reports its own close as well; this covers the status menu closing first.
    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        recentCaptures.hidePreview()
    }
```

- [ ] **Step 6: Build and run the tests**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 186 tests in 28 suites passed`.

- [ ] **Step 7: Check the preview by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Open Recent Captures and move the mouse onto a thumbnail. Expected: the capture appears, up to 560 by 420 points, in a rounded panel to the left of the submenu, level with the row and above the menu; moving down to the next thumbnail moves it to that row and shows that capture; moving onto a row's name or buttons hides it; closing the menu (Escape, a click elsewhere, or any row action) hides it; an upload-only capture shows its thumbnail-sized preview (it has no local file); with the menu bar item on a display's far left edge the panel opens to the right of the submenu. The menu stays open and keeps tracking while the panel shows, and the frontmost app stays active.

- [ ] **Step 8: Fallback when the panel does not appear above the menu (conditional)**

Apply this step only if, in Step 7, the panel never appears while the menu is open (verification on macOS 27 says it does; this is for a later macOS that changes it). It shows the larger image inside the hovered row instead: the row grows to 168 points and the thumbnail to 208 by 156 while the mouse is over it, and the panel and its placement are removed.

In `TidyShot/RecentCaptures/RecentCaptureRow.swift`:

Replace:
```swift
@Observable
final class RecentCaptureRowState {
    var isHighlighted = false
}
```
with:
```swift
@Observable
final class RecentCaptureRowState {
    var isHighlighted = false
    /// The larger preview while the thumbnail is hovered; the row grows to show it.
    var enlargedImage: NSImage?
}
```

Replace:
```swift
    static let thumbnailFrame = CGRect(x: horizontalPadding, y: (size.height - thumbnailSize.height) / 2,
                                       width: thumbnailSize.width, height: thumbnailSize.height)
```
with:
```swift
    static let thumbnailFrame = CGRect(x: horizontalPadding, y: (size.height - thumbnailSize.height) / 2,
                                       width: thumbnailSize.width, height: thumbnailSize.height)
    static let enlargedHeight: CGFloat = 168
    static let enlargedThumbnailSize = CGSize(width: 208, height: 156)
    static let enlargedThumbnailFrame = CGRect(x: horizontalPadding, y: (enlargedHeight - enlargedThumbnailSize.height) / 2,
                                               width: enlargedThumbnailSize.width, height: enlargedThumbnailSize.height)
```

Replace:
```swift
        .padding(.horizontal, Self.horizontalPadding)
        .frame(width: Self.size.width, height: Self.size.height)
```
with:
```swift
        .padding(.horizontal, Self.horizontalPadding)
        .frame(width: Self.size.width, height: state.enlargedImage == nil ? Self.size.height : Self.enlargedHeight)
```

Replace:
```swift
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
```
with:
```swift
            if let image = state.enlargedImage ?? thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: state.enlargedImage == nil ? Self.thumbnailSize.width : Self.enlargedThumbnailSize.width,
               height: state.enlargedImage == nil ? Self.thumbnailSize.height : Self.enlargedThumbnailSize.height)
```

In `TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift`:

Replace:
```swift
        let thumbnail = NSTrackingArea(rect: RecentCaptureRow.thumbnailFrame, options: options, owner: self, userInfo: nil)
```
with:
```swift
        let thumbnailRect = state.enlargedImage == nil ? RecentCaptureRow.thumbnailFrame : RecentCaptureRow.enlargedThumbnailFrame
        let thumbnail = NSTrackingArea(rect: thumbnailRect, options: options, owner: self, userInfo: nil)
```

Replace:
```swift
    override func mouseEntered(with event: NSEvent) {
```
with:
```swift
    /// Grows the row to show `image` in place of the thumbnail; nil shrinks it back. The menu lays
    /// its items out again when an item view's height changes, and the row's top stays where it
    /// was, so the larger image stays under the mouse.
    func showEnlarged(_ image: NSImage?) {
        state.enlargedImage = image
        setFrameSize(NSSize(width: RecentCaptureRow.size.width,
                            height: image == nil ? RecentCaptureRow.size.height : RecentCaptureRow.enlargedHeight))
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
```

In `TidyShot/RecentCaptures/RecentCapturesMenu.swift`:

Replace:
```swift
    private let previewPanel = PreviewPanel()
    /// The record whose thumbnail is under the mouse. A preview that finishes loading after the
    /// mouse moved on is dropped.
    private var hoveredID: UUID?
```
with:
```swift
    /// The row whose thumbnail is under the mouse. A preview that finishes loading after the mouse
    /// moved on is dropped.
    private weak var hoveredView: RecentCaptureMenuItemView?
```

Replace:
```swift
    /// Hides the preview; also called by `StatusMenuController` when the status menu closes.
    func hidePreview() {
        hoveredID = nil
        previewPanel.hide()
    }
```
with:
```swift
    /// Shrinks the enlarged row; also called by `StatusMenuController` when the status menu closes.
    func hidePreview() {
        hoveredView?.showEnlarged(nil)
        hoveredView = nil
    }
```

Replace:
```swift
    /// Loads the preview (up to 1200 px, off the main thread, cached by `ThumbnailProvider`) and
    /// shows it beside the submenu, level with the hovered row. The row view's window is the
    /// submenu's window, so its frame says where the submenu is on screen.
    private func thumbnailHover(_ view: RecentCaptureMenuItemView, inside: Bool) {
        guard inside else {
            if hoveredID == view.recordID { hidePreview() }
            return
        }
        guard let record = coordinator.history.record(id: view.recordID) else { return }
        hoveredID = record.id
        let provider = coordinator.thumbnailProvider
        Task { [weak self, weak view] in
            let image = await provider.preview(for: record)
            guard let self, let view, let image, self.hoveredID == record.id,
                  let menuWindow = view.window, let screen = menuWindow.screen ?? NSScreen.main else { return }
            let rowFrame = menuWindow.convertToScreen(view.convert(view.bounds, to: nil))
            let frame = PreviewPlacement.frame(imageSize: image.size, menuFrame: menuWindow.frame,
                                               rowFrame: rowFrame, visibleFrame: screen.visibleFrame)
            self.previewPanel.show(image, frame: frame)
        }
    }
```
with:
```swift
    /// Loads the preview (up to 1200 px, off the main thread, cached by `ThumbnailProvider`) and
    /// shows it in the hovered row, which grows to hold it.
    private func thumbnailHover(_ view: RecentCaptureMenuItemView, inside: Bool) {
        guard inside else {
            if hoveredView === view { hidePreview() }
            return
        }
        guard let record = coordinator.history.record(id: view.recordID) else { return }
        hidePreview()
        hoveredView = view
        let provider = coordinator.thumbnailProvider
        Task { [weak self, weak view] in
            let image = await provider.preview(for: record)
            guard let self, let view, let image, self.hoveredView === view else { return }
            view.showEnlarged(image)
        }
    }
```

Then remove the panel, its placement and their tests:
```bash
git rm TidyShot/RecentCaptures/PreviewPanel.swift TidyShot/RecentCaptures/PreviewPlacement.swift TidyShotTests/PreviewPlacementTests.swift
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 182 tests in 27 suites passed`. Check by hand: hovering a thumbnail grows its row and shows the larger image; leaving it shrinks the row. Use 182 in 27 instead of 186 in 28 wherever later steps state a total, and say in the Task 9 report that the fallback was applied.

- [ ] **Step 9: Commit**

```bash
git add TidyShot/RecentCaptures TidyShotTests/PreviewPlacementTests.swift TidyShot/App/StatusMenuController.swift
git commit -m "feat: full-size preview beside the Recent Captures submenu"
```
If Step 8 was applied, the commit message is `feat: enlarged preview inside the hovered Recent Captures row` and `git add -A TidyShot/RecentCaptures TidyShotTests` stages the removals.

---

### Task 9: Manual checklist, README, end-to-end check

**Files:**
- Create: `docs/testing/phase-3-1-manual-checklist.md`
- Modify: `docs/testing/phase-3-manual-checklist.md` (one note)
- Modify: `README.md` (two edits)

**Interfaces:**
- Consumes: everything from Tasks 1 to 8.
- Produces: the Phase 3.1 checklist, README sections that describe the submenu, the two delete alerts and Copy Image.

- [ ] **Step 1: Write the manual checklist**

`docs/testing/phase-3-1-manual-checklist.md`:
````markdown
# Phase 3.1 manual test checklist

Run after any change to the menu bar item, Recent Captures, Delete, Copy Image, the Upload tab or
the selection overlay. Automated tests cover the template migration, the luminance sampling, the
signed GET, the alert texts, the row text and the preview placement; everything here needs a
real menu bar, a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, after-capture action "Upload and copy URL", at least three captures in
history: one uploaded, one saved without upload ("Save and copy image"), one upload-only, and one
made before this build. Where the Phase 2 and Phase 3 checklists say Recent Captures shows
`Saved` or `Failed`, the submenu row shows no suffix or "· Upload failed".

## Menu bar
- [ ] One TidyShot icon (the viewfinder), no Dock icon. Opening the menu leaves the frontmost app active: its name stays in the menu bar.
- [ ] Items in order: Capture Area `⌃⇧4`, Capture Window `⌃⇧2`, Capture Fullscreen `⌃⇧3`, Recent Captures (with a chevron), Retry Failed Uploads (only with a failed upload), Reveal Last Capture, Settings… `⌘,`, Quit TidyShot `⌘Q`.
- [ ] Change the area shortcut in Settings > Shortcuts, reopen the menu: the title shows the new shortcut. Put it back.
- [ ] Each capture item starts its capture. Reveal Last Capture is disabled before the first save in this launch, then reveals the file.
- [ ] Settings… opens the Settings window in front of the frontmost app, again after closing it, and from `⌘,` while the menu is open.
- [ ] Network Link Conditioner (or a large fullscreen capture): during the upload the icon is `arrow.up.circle`, also while the menu is open, and returns to the viewfinder afterwards.
- [ ] With a failed upload in history, Retry Failed Uploads retries it and disappears from the menu once nothing has failed.
- [ ] Revoke Screen Recording and relaunch: the first item is "Screen Recording permission needed…" and opens the permission window.

## Recent Captures
- [ ] Hovering Recent Captures opens the submenu without a click; it lists the newest captures first, never more than 15 (take a 16th: the oldest row drops off).
- [ ] Each row shows a thumbnail, the object name (`aSIS7x.png`) or the file name, and the time: "now", "2 minutes ago", "yesterday"; an upload in flight adds "· Uploading", a failed one "· Upload failed". A capture made before Phase 3 gets its thumbnail on first display.
- [ ] The row under the mouse is highlighted; the menu highlight never sticks to a row the mouse has left.
- [ ] Clicking an uploaded row closes the menu and puts the URL on the clipboard; clicking a never-uploaded row puts the file there (paste in Finder makes a copy).
- [ ] The link button is greyed out on a never-uploaded row; on an uploaded row it closes the menu and copies the URL.
- [ ] The photo button on a saved capture closes the menu, posts "Image copied", and Notes pastes the image at point size, not double.
- [ ] The photo button on an upload-only capture (no local file) posts "Copying image…", then "Image copied", and the paste works; with Wi-Fi off it posts "Could not copy image" with the reason.
- [ ] The photo button is greyed out on a capture made before Phase 3 whose file was deleted from the save folder.
- [ ] The trash button closes the menu and shows the delete alert (see Delete); after Delete the row is gone the next time the menu opens.
- [ ] With an empty history the submenu shows a greyed "No captures yet".

## Preview
- [ ] Moving onto a thumbnail shows the capture in a rounded panel to the left of the submenu, above the menu, level with the row, at most 560 by 420 points; the menu stays open and the frontmost app stays active.
- [ ] Moving to the next thumbnail moves the panel to that row with that capture; moving onto a name or a button hides it; Escape, a click outside, or any row action hides it with the menu.
- [ ] An upload-only capture previews at thumbnail size (it has no local file to decode).
- [ ] With the submenu at the left edge of a display (menu bar item far left, or a narrow display) the panel opens on the right of the submenu instead and stays on screen.

## Delete
- [ ] Uploaded capture, from the trash button or the overlay: "Delete this capture?", "Removes it from object storage and from history.", Delete (red) and Cancel. Escape cancels. Delete removes the row, the object (`curl -I <url>` gives 403 or 404), the file in the save folder and the thumbnail.
- [ ] Saved capture never uploaded: the line reads "Removes it from your save folder and from history."; a capture uploaded before Phase 3: "Removes it from your save folder and from history. The uploaded object stays in the bucket."
- [ ] Wi-Fi off, Delete on an uploaded capture: a second alert, "Couldn't delete it from storage: …" with "Remove it from history anyway? The object stays in the bucket." and Remove (red) and Cancel. Cancel keeps the capture. Delete again, Remove: the row and thumbnail go, the file in the save folder stays, and with Wi-Fi back on `curl -I <url>` still gives 200.
- [ ] The same with an upload-only capture that has failed and is still in `pending/`: after Remove, its `pending/<UUID>.png` is gone.
- [ ] Forget Credentials, then Delete on an uploaded capture: the second alert says "Couldn't delete it from storage: No credentials are saved in Settings > Upload." Re-enter the credentials.
- [ ] Network Link Conditioner at 100% loss, Delete on an uploaded capture, then the trash button in the overlay and in the submenu for the same capture while the request hangs: no second alert appears.

## Templates and Upload tab
- [ ] Before installing this build, with the Phase 3 build, set the file name template to `{app} {datetime}` and the key template to `shots/{app}/{random:8}` and save. After launching this build: Settings > General shows `{datetime}`, Settings > Upload shows `shots/{random:8}`, and `defaults read ~/Library/Containers/io.tky.tidyshot/Data/Library/Preferences/io.tky.tidyshot.plist` shows neither template with the old token. A capture uploads to `shots/XXXXXXXX.png`.
- [ ] The token captions in Settings > General and Settings > Upload list `{date} {year} {month} {day} {time} {datetime} {hostname} {counter} {random} {random:8}`.
- [ ] An empty Endpoint and Public URL each show a grey "Required"; the example sits on its own caption line under each field.
- [ ] Save and Test Connection with correct settings reports exactly "Upload and public read both work." with no URL after it; a wrong secret still reports "Upload failed: …".
- [ ] The Upload tab shows everything down to the Save buttons without scrolling, with the key template's orange warning showing.

## Crosshair
- [ ] `⌃⇧4` over a white window: after the first moment (white crosshair with a thin dark edge) the crosshair is black; over a dark window it is white; moving between them switches it.
- [ ] Dragging a rectangle across light and dark areas: its border takes the colour for the area under the cursor.
- [ ] Two displays with different backgrounds: each overlay picks the colour from its own display.
````

- [ ] **Step 2: Point the Phase 3 checklist at the new one**

In `docs/testing/phase-3-manual-checklist.md`:

Replace:
```markdown
# Phase 3 manual test checklist

```
with:
```markdown
# Phase 3 manual test checklist

Phase 3.1 replaced the gallery window with the Recent Captures submenu and the three-button delete
alert with a two-button one. Skip the Gallery section and the "Remove from History Only" items
below; `docs/testing/phase-3-1-manual-checklist.md` covers them now.

```

- [ ] **Step 3: Update the README**

In `README.md`:

Replace:
```markdown
## Recent Captures

The menu's Recent Captures… item opens a gallery of thumbnails, newest first. Hover for a larger
preview, click to copy the URL (or the file when it was never uploaded), and use the context menu
to retry a failed upload, reveal the file, or delete the capture, which removes the object from
the bucket it was uploaded to, the local file, the thumbnail and the history entry after one
confirmation. The confirmation also offers Remove from History Only, which drops just the entry
and keeps the object and the file. The Quick Access overlay has the same Delete; while an upload
is still running it cancels it first.
```
with:
```markdown
## Recent Captures

Hover Recent Captures in the menu bar menu for the newest 15 captures, each with a thumbnail, its
name and how long ago it was taken. Click a row to copy its URL (or the file when it was never
uploaded). The row's buttons copy the URL, copy the image (downloaded from the bucket with a
signed request when no local file is left), or delete the capture. Hover a thumbnail to see the
capture full size beside the menu.

Delete asks once, "Delete this capture?", then removes the object from the bucket it was uploaded
to, the local file, the thumbnail and the history entry. If the bucket refuses the delete, a
second alert offers to remove the capture from history anyway and leave the object where it is.
The Quick Access overlay has the same Delete; while an upload is still running it cancels it
first. Retry Failed Uploads appears in the menu whenever an upload has failed.
```

Replace:
```markdown
- Phase 3 manual test checklist: `docs/testing/phase-3-manual-checklist.md`
```
with:
```markdown
- Phase 3 manual test checklist: `docs/testing/phase-3-manual-checklist.md`
- Phase 3.1 manual test checklist: `docs/testing/phase-3-1-manual-checklist.md`
```

- [ ] **Step 4: Run the full suite and the checks**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 186 tests in 28 suites passed`.

Then:
```bash
grep -rn "{app}" TidyShot README.md | grep -v -e "TidyShot/Output/TemplateMigration.swift" -e "TidyShot/Settings/AppSettings.swift" -e "TidyShot/Upload/S3DestinationConfig.swift"; grep -rni "gallery\|MenuBarExtra\|Remove from History Only" TidyShot README.md
```
Expected: no output.

- [ ] **Step 5: Run the end-to-end check**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Press `⌃⇧4` over a light window (the crosshair is black), drag a rectangle, paste into Slack: a working `https://snap.tky.io/…` link. Open the menu, hover Recent Captures, hover the new row's thumbnail (the preview appears to the left), click the photo button and paste into Notes (the image), then the trash button, Delete: the link returns 403 or 404 and the row is gone. Then work through `docs/testing/phase-3-1-manual-checklist.md`, and, because the menu bar and the delete flow changed, the "Overlay delete", "Upload only" and "Forget credentials" sections of `docs/testing/phase-3-manual-checklist.md` (where an item says Recent Captures or the gallery, use the submenu).

- [ ] **Step 6: Commit**

```bash
git add docs/testing/phase-3-1-manual-checklist.md docs/testing/phase-3-manual-checklist.md README.md
git commit -m "docs: Phase 3.1 checklist and README"
```

- [ ] **Step 7: Stop here**

Phase 3.1 is done when the checklists pass and the last test run reads `Test run with 186 tests in 28 suites passed` (182 in 27 if Task 8 Step 8 was applied). Do not push and do not open a PR: stop here; the controller pushes and opens the PR after the whole-branch review. Report the final test line, the checklist results, and whether the Task 8 fallback was needed.

---

## Out of scope for this plan (next plans)

- Phase 4 annotation, Phase 5 scrolling capture, Phase 6 overlay and capture polish, Phase 7 extras, as in the spec.
- Live updates of an open Recent Captures submenu (rows refresh when the menu next opens), keyboard navigation inside the rows, and a "Show all" window for captures beyond the newest 15.
- Retry from a Recent Captures row (Retry Failed Uploads in the menu covers it) and Reveal in Finder from a row.
- Copy Image for records uploaded before Phase 3 whose local file is gone (they have no stored location to sign a GET for).
