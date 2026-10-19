# TidyShot Phase 0 and 1: Capture and Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sandboxed macOS 26 menu bar app that captures an area, a window, or a full display with ScreenCaptureKit, saves a Retina-correct PNG to a user-chosen folder, copies it to the clipboard, and notifies the user.

**Architecture:** A single `AppCoordinator` wires global hotkeys to a `SelectionController` (borderless overlay windows for area and window picking), then to a `CaptureEngine` (ScreenCaptureKit `SCScreenshotManager`), then to an output pipeline (`ImageEncoder`, `FileNamer`, `SaveLocation`, `Pasteboard`, `Notifier`). Pure logic (geometry, naming, encoding) lives in small files with Swift Testing tests. AppKit owns the overlay windows; SwiftUI owns the menu bar menu and the Settings window.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation, SwiftUI `MenuBarExtra` and `Settings`, AppKit for overlay windows, ScreenCaptureKit (`SCScreenshotConfiguration`, `SCScreenshotManager.captureScreenshot`), ImageIO, UserNotifications, `KeyboardShortcuts` 3.1.0 (sindresorhus), XcodeGen 2.46, Swift Testing.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`.

## Global Constraints

- Minimum macOS: `26.0`. Xcode 27.1, macOS 27.0 SDK. Capture uses `SCScreenshotConfiguration` and `SCScreenshotManager.captureScreenshot(contentFilter:configuration:)`; never `CGWindowListCreateImage`, never `captureImage(contentFilter:configuration:)`.
- App Sandbox on. Entitlements in this phase: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope`. The save folder is chosen with `NSOpenPanel` and persisted as a security-scoped bookmark.
- Bundle identifier `io.tky.tidyshot`. Product name `TidyShot`. Menu bar agent (`LSUIElement` true).
- XcodeGen `project.yml` is the source of truth. `TidyShot.xcodeproj`, `.build/`, and `Config/Local.xcconfig` are gitignored.
- Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Everything is main-actor unless marked `nonisolated`.
- Output format PNG only, with DPI metadata equal to 72 times the display scale factor.
- Default file name template: `Screenshot {date} at {time}`. Tokens: `{date}`, `{time}`, `{datetime}`, `{app}`, `{counter}`, `{random}`, `{random:N}`. The `.png` extension is appended automatically. Duplicate names get ` 2`, ` 3`, and so on.
- Default hotkeys: area `⌃⇧4`, window `⌃⇧2`, fullscreen `⌃⇧3`. All rebindable in Settings.
- Cursor is hidden in captures by default (`showsCursor = false`), with a setting to show it.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), run with `xcodebuild test`. The test host is the app itself; `AppDelegate` skips `AppCoordinator.start()` when running under XCTest.
- The selection overlay stays on screen while the capture is taken and is excluded from the ScreenCaptureKit content filter by window; capture never relies on hide-then-wait timing.
- No GPL-licensed code may be read or copied. The project is private.
- Commit after every task with a conventional commit message. Never include a Claude Code session URL in a commit or PR.

## Build and test commands used throughout

```bash
# regenerate the project after any project.yml change
xcodegen generate
```

```bash
# build (exit code 0 on success)
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet
```

```bash
# run all unit tests
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet
```

```bash
# launch the built app
open .build/Build/Products/Debug/TidyShot.app
```

Code signing note: this Mac has no Apple Development identity, so `Config/Local.xcconfig` uses ad-hoc signing (`CODE_SIGN_IDENTITY = -`). With ad-hoc signing, macOS treats every rebuild as a different app for Screen Recording permission, so the permission must be re-granted after each rebuild during development. To avoid that, sign in to Xcode with an Apple ID (Xcode > Settings > Accounts), then set `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY = Apple Development` in `Config/Local.xcconfig`. The plan works either way.

## File structure

```
project.yml                                  XcodeGen spec
.gitignore
Config/Local.xcconfig.example                committed signing defaults (ad-hoc)
Config/Local.xcconfig                        gitignored copy, may hold a team id
TidyShot/
  App/
    TidyShotApp.swift                        @main, MenuBarExtra + Settings scenes
    AppDelegate.swift                        starts AppCoordinator
    AppCoordinator.swift                     hotkeys -> selection -> capture -> output
    MenuContent.swift                        menu bar menu
    Shortcuts.swift                          KeyboardShortcuts.Name definitions
  Capture/
    ScreenCapturePermission.swift            TCC preflight/request/open settings
    PermissionWindowController.swift         first-run permission window (SwiftUI in NSWindow)
    Geometry.swift                           AppKit <-> CoreGraphics coordinate math (pure)
    CaptureTarget.swift                      CaptureTarget, CaptureOptions, CaptureResult, CaptureError
    CaptureEngine.swift                      ScreenCaptureKit wrapper
  Selection/
    Selection.swift                          SelectionMode, Selection
    SelectionWindow.swift                    borderless full-screen NSWindow
    SelectionView.swift                      dimming, crosshair, drag rect, size label, highlight, loupe
    SelectionController.swift                one window per screen, returns Selection
    WindowPicker.swift                       cursor -> SCWindow
  Output/
    ImageEncoder.swift                       CGImage -> PNG Data with DPI (pure)
    FileNamer.swift                          template engine + unique URL (pure)
    SaveLocation.swift                       security-scoped bookmark + NSOpenPanel
    Pasteboard.swift                         clipboard writes
    Notifier.swift                           UNUserNotificationCenter
    SoundPlayer.swift                        shutter sound
  Resources/
    Assets.xcassets                          AppIcon placeholder
  Settings/
    AppSettings.swift                        @Observable, UserDefaults-backed
    SettingsView.swift                       TabView shell
    GeneralSettingsView.swift
    ShortcutsSettingsView.swift
    CaptureSettingsView.swift
TidyShotTests/
  SmokeTests.swift
  GeometryTests.swift
  FileNamerTests.swift
  ImageEncoderTests.swift
  WindowPickerTests.swift
docs/testing/phase-1-manual-checklist.md
README.md
```

---

### Task 1: Project scaffold and menu bar agent

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `Config/Local.xcconfig.example`
- Create: `TidyShot/App/TidyShotApp.swift`
- Create: `TidyShot/App/AppDelegate.swift`
- Create: `TidyShot/App/AppCoordinator.swift`
- Create: `TidyShot/App/MenuContent.swift`
- Create: `TidyShotTests/SmokeTests.swift`
- Create: `TidyShot/Resources/Assets.xcassets/Contents.json`
- Create: `TidyShot/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

**Interfaces:**
- Produces: `AppCoordinator.shared` (singleton, `@Observable`, main actor) with `func start()`. Later tasks add methods to it.

- [ ] **Step 1: Install XcodeGen**

Run:
```bash
brew install xcodegen
```
Expected: `xcodegen --version` prints `Version: 2.46.0` or newer.

Run once on a fresh Xcode install, otherwise the first `xcodebuild` fails with "failed to load a required plug-in ... IDESimulatorFoundation":
```bash
xcodebuild -runFirstLaunch
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
# Generated by XcodeGen; regenerate with `xcodegen generate`
*.xcodeproj
# Build output
.build/
DerivedData/
build/
# Local signing settings
Config/Local.xcconfig
# Xcode user state
xcuserdata/
*.xcuserstate
.swiftpm/
.DS_Store
```

- [ ] **Step 3: Write `Config/Local.xcconfig.example` and copy it**

```xcconfig
// Copy this file to Config/Local.xcconfig (gitignored).
// Default: ad-hoc signing, works without an Apple ID. Screen Recording permission
// must be re-granted after every rebuild with ad-hoc signing.
// With an Apple ID signed in to Xcode, set:
//   CODE_SIGN_IDENTITY = Apple Development
//   DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =
```

Run:
```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

- [ ] **Step 4: Write `project.yml`**

```yaml
name: TidyShot

options:
  bundleIdPrefix: io.tky
  xcodeVersion: "27.1"
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true

configFiles:
  Debug: Config/Local.xcconfig
  Release: Config/Local.xcconfig

packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 3.1.0

targets:
  TidyShot:
    type: application
    platform: macOS
    sources:
      - path: TidyShot
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.tky.tidyshot
        PRODUCT_NAME: TidyShot
        SWIFT_VERSION: "6.0"
        SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
        SWIFT_APPROACHABLE_CONCURRENCY: YES
        ENABLE_APP_SANDBOX: YES
        ENABLE_HARDENED_RUNTIME: YES
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        COMBINE_HIDPI_IMAGES: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    info:
      path: TidyShot/Info.plist
      properties:
        CFBundleName: TidyShot
        CFBundleDisplayName: TidyShot
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        LSUIElement: true
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "Copyright © 2026 Tim Yocum"
    entitlements:
      path: TidyShot/TidyShot.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.files.user-selected.read-write: true
        com.apple.security.files.bookmarks.app-scope: true
    dependencies:
      - package: KeyboardShortcuts
    scheme:
      testTargets:
        - TidyShotTests

  TidyShotTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: TidyShotTests
    settings:
      base:
        SWIFT_VERSION: "6.0"
        SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
        SWIFT_APPROACHABLE_CONCURRENCY: YES
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: TidyShot
```

- [ ] **Step 5: Write the app entry point**

`TidyShot/App/TidyShotApp.swift`:
```swift
import SwiftUI

@main
struct TidyShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("TidyShot", systemImage: "camera.viewfinder") {
            MenuContent()
        }
    }
}
```

`TidyShot/App/AppDelegate.swift`:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when this process is the unit-test host; the coordinator must not start then.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppCoordinator.shared.start()
    }
}
```

`TidyShot/App/AppCoordinator.swift`:
```swift
import AppKit
import Observation

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
/// Later tasks add capture methods here.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    func start() {
        NSLog("TidyShot started")
    }
}
```

`TidyShot/App/MenuContent.swift`:
```swift
import SwiftUI

struct MenuContent: View {
    var body: some View {
        Button("Quit TidyShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

- [ ] **Step 6: Add an empty asset catalog with an AppIcon placeholder**

`TidyShot/Resources/Assets.xcassets/Contents.json`:
```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`TidyShot/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` (no images yet; the app shows the generic icon until a real one is added):
```json
{
  "images" : [
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 7: Write the smoke test**

`TidyShotTests/SmokeTests.swift`:
```swift
import Testing
@testable import TidyShot

struct SmokeTests {
    @Test func coordinatorSingletonExists() {
        #expect(AppCoordinator.shared === AppCoordinator.shared)
    }
}
```

- [ ] **Step 8: Generate, build, test**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && echo BUILD_OK
```
Expected: `BUILD_OK`. If Xcode reports "Signing for TidyShot requires a development team", confirm `Config/Local.xcconfig` exists with `CODE_SIGN_IDENTITY = -`.

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet && echo TESTS_OK
```
Expected: `TESTS_OK` and a line containing `Test run with 1 test in 1 suite passed`. (An `Executed 0 tests` XCTest line also appears; that is normal when all tests use Swift Testing.)

- [ ] **Step 9: Launch and check the menu bar**

Run:
```bash
open .build/Build/Products/Debug/TidyShot.app
```
Expected: a viewfinder icon appears in the menu bar, no Dock icon, and the menu shows "Quit TidyShot". Quit it from the menu.

- [ ] **Step 10: Commit**

```bash
git add .gitignore project.yml Config/Local.xcconfig.example TidyShot TidyShotTests
git commit -m "feat: scaffold TidyShot menu bar agent with XcodeGen"
```

---

### Task 2: Screen Recording permission flow

**Files:**
- Create: `TidyShot/Capture/ScreenCapturePermission.swift`
- Create: `TidyShot/Capture/PermissionWindowController.swift`
- Modify: `TidyShot/App/AppCoordinator.swift`
- Modify: `TidyShot/App/MenuContent.swift`

**Interfaces:**
- Produces: `ScreenCapturePermission.isGranted: Bool`, `ScreenCapturePermission.request() -> Bool`, `ScreenCapturePermission.openSystemSettings()`, `PermissionWindowController.show()`.
- Produces on `AppCoordinator`: `var permissionGranted: Bool`, `func showPermissionWindow()`.

- [ ] **Step 1: Write the permission helper**

`TidyShot/Capture/ScreenCapturePermission.swift`:
```swift
import AppKit
import CoreGraphics

/// Screen Recording (TCC) permission checks. ScreenCaptureKit requires this permission for every
/// capture that is not driven by the system content picker.
enum ScreenCapturePermission {
    /// True when this app has Screen Recording permission. Does not prompt.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time. Later calls return the current state without prompting.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Opens System Settings > Privacy & Security > Screen & System Audio Recording.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Write the permission window**

`TidyShot/Capture/PermissionWindowController.swift`:
```swift
import AppKit
import SwiftUI

struct PermissionView: View {
    @State private var isGranted = ScreenCapturePermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Screen Recording access needed", systemImage: "camera.viewfinder")
                .font(.title2.bold())
            Text("TidyShot captures your screen with Apple's ScreenCaptureKit, which requires Screen Recording permission. Nothing is captured until you press a capture shortcut.")
                .fixedSize(horizontal: false, vertical: true)
            if isGranted {
                Label("Access granted. Quit and reopen TidyShot to finish.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Quit TidyShot") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            } else {
                HStack {
                    Button("Request Access") {
                        ScreenCapturePermission.request()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Open System Settings") {
                        ScreenCapturePermission.openSystemSettings()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .task {
            while !Task.isCancelled {
                isGranted = ScreenCapturePermission.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Shows the first-run permission window. Safe to call repeatedly; reuses the window.
final class PermissionWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionView())
            let newWindow = NSWindow(contentViewController: hosting)
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

- [ ] **Step 3: Wire it into the coordinator and menu**

`TidyShot/App/AppCoordinator.swift`:
```swift
import AppKit
import Observation

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    private let permissionWindow = PermissionWindowController()

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    func start() {
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }
}
```

`TidyShot/App/MenuContent.swift`:
```swift
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
        Button("Quit TidyShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

- [ ] **Step 4: Build and verify manually**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected: the permission window appears on first launch. "Request Access" shows the macOS prompt (or does nothing if already asked once). "Open System Settings" opens the Screen & System Audio Recording pane. After enabling TidyShot there, within one second the window shows the green "Access granted" line and a "Quit TidyShot" button. Relaunch: no permission window, no permission menu item.

- [ ] **Step 5: Commit**

```bash
git add TidyShot
git commit -m "feat: add Screen Recording permission flow"
```

---

### Task 3: Geometry helpers (TDD)

**Files:**
- Create: `TidyShot/Capture/Geometry.swift`
- Create: `TidyShotTests/GeometryTests.swift`

**Interfaces:**
- Produces:
  - `Geometry.cgRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect`
  - `Geometry.appKitRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> CGRect`
  - `Geometry.cgPoint(fromAppKit point: CGPoint, primaryHeight: CGFloat) -> CGPoint`
  - `Geometry.displayLocal(_ rect: CGRect, in displayFrame: CGRect) -> CGRect`
  - `Geometry.pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int)`

Background: AppKit global coordinates have their origin at the bottom-left of the primary screen (`NSScreen.screens[0]`) with y increasing upward. CoreGraphics and ScreenCaptureKit (`SCDisplay.frame`, `SCWindow.frame`, `SCScreenshotConfiguration.sourceRect`) use the top-left of the primary display with y increasing downward. Both share the same x axis. `sourceRect` is relative to the display's own top-left corner, in points.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/GeometryTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct GeometryTests {
    let primaryHeight: CGFloat = 1080

    @Test func appKitRectToCGFlipsY() {
        let appKit = CGRect(x: 100, y: 100, width: 200, height: 50)
        let cg = Geometry.cgRect(fromAppKit: appKit, primaryHeight: primaryHeight)
        #expect(cg == CGRect(x: 100, y: 930, width: 200, height: 50))
    }

    @Test func cgRectToAppKitRoundTrips() {
        let appKit = CGRect(x: -300, y: 1200, width: 640, height: 480)
        let cg = Geometry.cgRect(fromAppKit: appKit, primaryHeight: primaryHeight)
        let back = Geometry.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        #expect(back == appKit)
    }

    @Test func appKitPointToCG() {
        let point = Geometry.cgPoint(fromAppKit: CGPoint(x: 10, y: 1070), primaryHeight: primaryHeight)
        #expect(point == CGPoint(x: 10, y: 10))
    }

    @Test func displayLocalOnSecondaryDisplayToTheLeft() {
        let displayFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let global = CGRect(x: -500, y: 200, width: 100, height: 100)
        let local = Geometry.displayLocal(global, in: displayFrame)
        #expect(local == CGRect(x: 1420, y: 200, width: 100, height: 100))
    }

    @Test func displayLocalOnDisplayAbovePrimary() {
        let displayFrame = CGRect(x: 0, y: -900, width: 1440, height: 900)
        let global = CGRect(x: 10, y: -890, width: 50, height: 50)
        let local = Geometry.displayLocal(global, in: displayFrame)
        #expect(local == CGRect(x: 10, y: 10, width: 50, height: 50))
    }

    @Test func pixelSizeRoundsToNearestPixel() {
        let size = Geometry.pixelSize(points: CGSize(width: 100.4, height: 50.6), scale: 2)
        #expect(size.width == 201)
        #expect(size.height == 101)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'Geometry' in scope`.

- [ ] **Step 3: Implement Geometry**

`TidyShot/Capture/Geometry.swift`:
```swift
import CoreGraphics

/// Coordinate conversions between AppKit global space (origin bottom-left of the primary screen,
/// y up) and CoreGraphics / ScreenCaptureKit global space (origin top-left of the primary display,
/// y down). `primaryHeight` is `NSScreen.screens[0].frame.height`.
enum Geometry {
    static func cgRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cgPoint(fromAppKit point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Converts a CG-global rect into the coordinate system of a display whose CG-global frame is `displayFrame`.
    static func displayLocal(_ rect: CGRect, in displayFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((points.width * scale).rounded()), Int((points.height * scale).rounded()))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: a line containing `Test run with 7 tests in 2 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Capture/Geometry.swift TidyShotTests/GeometryTests.swift
git commit -m "feat: add AppKit/CoreGraphics geometry helpers"
```

---

### Task 4: FileNamer template engine (TDD)

**Files:**
- Create: `TidyShot/Output/FileNamer.swift`
- Create: `TidyShotTests/FileNamerTests.swift`

**Interfaces:**
- Produces:
  - `FileNamer.defaultTemplate: String` (`"Screenshot {date} at {time}"`)
  - `FileNamer(template:now:randomString:)`
  - `FileNamer.name(appName: String?, counter: Int) -> String` (no extension)
  - `FileNamer.sanitize(_:) -> String`
  - `FileNamer.randomString(length: Int) -> String`
  - `FileNamer.uniqueURL(baseName: String, ext: String, in directory: URL, fileManager: FileManager) -> URL`

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/FileNamerTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct FileNamerTests {
    /// 2026-10-19 11:56:03 in the current time zone, matching what DateFormatter will print.
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!

    func namer(_ template: String) -> FileNamer {
        FileNamer(template: template, now: { fixedDate }, randomString: { String(repeating: "X", count: $0) })
    }

    @Test func defaultTemplateMatchesSystemStyle() {
        let name = FileNamer(now: { fixedDate }).name(appName: nil, counter: 1)
        #expect(name == "Screenshot 2026-10-19 at 11.56.03")
    }

    @Test func appAndDatetimeTokens() {
        #expect(namer("{app} {datetime}").name(appName: "Safari", counter: 1) == "Safari 2026-10-19 11.56.03")
    }

    @Test func missingAppFallsBackToScreen() {
        #expect(namer("{app}").name(appName: nil, counter: 1) == "Screen")
    }

    @Test func counterToken() {
        #expect(namer("shot-{counter}").name(appName: nil, counter: 42) == "shot-42")
    }

    @Test func randomTokenDefaultsToSixCharacters() {
        #expect(namer("{random}").name(appName: nil, counter: 1) == "XXXXXX")
    }

    @Test func randomTokenWithLength() {
        #expect(namer("{random:8}-{random:2}").name(appName: nil, counter: 1) == "XXXXXXXX-XX")
    }

    @Test func sanitizeReplacesPathSeparatorsAndColons() {
        #expect(FileNamer.sanitize("a/b:c") == "a-b-c")
    }

    @Test func sanitizeTrimsWhitespaceAndLeadingDot() {
        #expect(FileNamer.sanitize("  .hidden ") == "_hidden")
    }

    @Test func emptyResultFallsBackToScreenshot() {
        #expect(namer("   ").name(appName: nil, counter: 1) == "Screenshot")
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

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'FileNamer' in scope`.

- [ ] **Step 3: Implement FileNamer**

`TidyShot/Output/FileNamer.swift`:
```swift
import Foundation

/// Expands a file name template. Tokens: {date} {time} {datetime} {app} {counter} {random} {random:N}.
/// The extension is not part of the template.
struct FileNamer {
    static let defaultTemplate = "Screenshot {date} at {time}"

    var template: String
    var now: () -> Date
    var randomString: (Int) -> String

    init(template: String = FileNamer.defaultTemplate,
         now: @escaping () -> Date = { Date() },
         randomString: @escaping (Int) -> String = FileNamer.randomString) {
        self.template = template
        self.now = now
        self.randomString = randomString
    }

    func name(appName: String?, counter: Int) -> String {
        let date = now()
        var result = template
        result = result.replacingOccurrences(of: "{datetime}", with: Self.format(date, "yyyy-MM-dd HH.mm.ss"))
        result = result.replacingOccurrences(of: "{date}", with: Self.format(date, "yyyy-MM-dd"))
        result = result.replacingOccurrences(of: "{time}", with: Self.format(date, "HH.mm.ss"))
        result = result.replacingOccurrences(of: "{app}", with: appName ?? "Screen")
        result = result.replacingOccurrences(of: "{counter}", with: String(counter))
        result = expandRandom(in: result)
        let sanitized = Self.sanitize(result)
        return sanitized.isEmpty ? "Screenshot" : sanitized
    }

    private func expandRandom(in input: String) -> String {
        let pattern = /\{random(?::(\d+))?\}/
        var result = input
        while let match = result.firstMatch(of: pattern) {
            let requested = match.output.1.flatMap { Int($0) } ?? 6
            let length = min(max(requested, 1), 64)
            result.replaceSubrange(match.range, with: randomString(length))
        }
        return result
    }

    static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
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

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: `Test run with 18 tests in 3 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Output/FileNamer.swift TidyShotTests/FileNamerTests.swift
git commit -m "feat: add file name template engine"
```

---

### Task 5: ImageEncoder with DPI metadata (TDD)

**Files:**
- Create: `TidyShot/Output/ImageEncoder.swift`
- Create: `TidyShotTests/ImageEncoderTests.swift`

**Interfaces:**
- Produces: `ImageEncoder.pngData(from image: CGImage, scale: CGFloat) throws -> Data`, `ImageEncoder.EncodeError`.

Background: a 2x Retina capture pasted into another app displays at double size unless the PNG carries `pHYs` DPI metadata. ImageIO writes it from `kCGImagePropertyDPIWidth` and `kCGImagePropertyDPIHeight`. 72 DPI is 1x; 144 is 2x.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ImageEncoderTests.swift`:
```swift
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TidyShot

struct ImageEncoderTests {
    func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func properties(of data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    }

    @Test func encodesPNGSignature() throws {
        let data = try ImageEncoder.pngData(from: makeImage(width: 4, height: 4), scale: 1)
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// PNG stores pixels per metre as an integer, so read-back can be off by a fraction of a DPI.
    func dpi(_ props: [CFString: Any], _ key: CFString) -> Double {
        props[key] as? Double ?? 0
    }

    @Test func retinaScaleWrites144DPI() throws {
        let data = try ImageEncoder.pngData(from: makeImage(width: 200, height: 100), scale: 2)
        let props = properties(of: data)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 100)
        #expect(abs(dpi(props, kCGImagePropertyDPIWidth) - 144) < 0.5)
        #expect(abs(dpi(props, kCGImagePropertyDPIHeight) - 144) < 0.5)
    }

    @Test func standardScaleWrites72DPI() throws {
        let data = try ImageEncoder.pngData(from: makeImage(width: 10, height: 10), scale: 1)
        let props = properties(of: data)
        #expect(abs(dpi(props, kCGImagePropertyDPIWidth) - 72) < 0.5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'ImageEncoder' in scope`.

- [ ] **Step 3: Implement ImageEncoder**

`TidyShot/Output/ImageEncoder.swift`:
```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoder {
    enum EncodeError: LocalizedError {
        case destinationUnavailable
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .destinationUnavailable: "Could not create a PNG encoder."
            case .finalizeFailed: "PNG encoding failed."
            }
        }
    }

    /// Encodes `image` as PNG with DPI metadata of `72 * scale`, so a 2x capture reports 144 DPI
    /// and displays at its point size when pasted.
    static func pngData(from image: CGImage, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw EncodeError.destinationUnavailable
        }
        let dpi = 72.0 * Double(scale)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodeError.finalizeFailed
        }
        return data as Data
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: `Test run with 21 tests in 4 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Output/ImageEncoder.swift TidyShotTests/ImageEncoderTests.swift
git commit -m "feat: add PNG encoder with Retina DPI metadata"
```

---

### Task 6: CaptureEngine over ScreenCaptureKit, with a debug fullscreen capture

**Files:**
- Create: `TidyShot/Capture/CaptureTarget.swift`
- Create: `TidyShot/Capture/CaptureEngine.swift`
- Modify: `TidyShot/App/AppCoordinator.swift`
- Modify: `TidyShot/App/MenuContent.swift`

**Interfaces:**
- Consumes: `Geometry.displayLocal`, `Geometry.pixelSize`, `Geometry.cgPoint`, `ImageEncoder.pngData`.
- Produces:
  - `enum CaptureTarget { case display(SCDisplay); case area(rect: CGRect, display: SCDisplay); case window(SCWindow) }` (rect in CG global points)
  - `struct CaptureOptions { var showsCursor: Bool }`
  - `struct CaptureResult { let image: CGImage; let scale: CGFloat; let target: CaptureTarget }`
  - `CaptureEngine.shareableContent() async throws -> SCShareableContent`
  - `CaptureEngine.capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [SCWindow]) async throws -> CaptureResult`
  - `CaptureEngine.scale(forDisplayID: CGDirectDisplayID) -> CGFloat`
  - `CaptureEngine.screen(forDisplayID: CGDirectDisplayID) -> NSScreen?`
  - `CaptureEngine.displayID(containing: CGRect) -> CGDirectDisplayID`
  - On `AppCoordinator`: `func captureFullscreen() async`, `func capture(_ target: CaptureTarget, excludingWindows: [SCWindow]) async -> CaptureResult?`, `func loadContent() async -> SCShareableContent?`, `static func display(under appKitPoint: CGPoint, in displays: [SCDisplay]) -> SCDisplay?`

Background, verified against the macOS 27.0 SDK header `SCScreenshotManager.h`:
- `SCScreenshotConfiguration` (macOS 26) has `width`, `height` (pixels), `showsCursor`, `sourceRect` (points, display-local), `destinationRect`, `ignoreShadows`, `ignoreClipping`, `includeChildWindows`, `displayIntent`, `dynamicRange` (`.sdr`, `.hdr`, `.bothSDRAndHDR`), `contentType`, `fileURL`.
- `SCScreenshotManager.captureScreenshot(contentFilter:configuration:) async throws -> SCScreenshotOutput`; `SCScreenshotOutput.sdrImage: CGImage?`. `CGImage` is `Sendable` in this SDK.
- `SCContentFilter(display:excludingWindows:)` and `SCContentFilter(desktopIndependentWindow:)`.
- `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:) async throws -> SCShareableContent`. The first call triggers the Screen Recording prompt if permission is missing and throws `SCStreamError.userDeclined` (-3801) when denied.
- Width and height must be set in pixels, or the output is blurry on Retina displays.
- Window captures set `ignoreShadows = true` in this phase. The spec lists a shadow toggle as a Phase 3 option; until then windows are captured without their shadow so the output size equals the window frame.

- [ ] **Step 1: Write the capture types**

`TidyShot/Capture/CaptureTarget.swift`:
```swift
import CoreGraphics
import ScreenCaptureKit

/// What to capture. Rects are in CoreGraphics global points (top-left origin).
enum CaptureTarget {
    case display(SCDisplay)
    case area(rect: CGRect, display: SCDisplay)
    case window(SCWindow)
}

struct CaptureOptions {
    var showsCursor: Bool = false
}

struct CaptureResult {
    let image: CGImage
    /// Backing scale factor of the display the capture came from (1 or 2).
    let scale: CGFloat
    let target: CaptureTarget
}

enum CaptureError: LocalizedError {
    case noImage

    var errorDescription: String? {
        switch self {
        case .noImage: "ScreenCaptureKit returned no image."
        }
    }
}
```

- [ ] **Step 2: Write the engine**

`TidyShot/Capture/CaptureEngine.swift`:
```swift
import AppKit
import ScreenCaptureKit

/// Thin wrapper over ScreenCaptureKit's one-shot screenshot API.
final class CaptureEngine {
    /// All on-screen displays and windows. The first call prompts for Screen Recording permission.
    func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Captures `target`. `excludingWindows` removes windows (such as our own overlay) from display
    /// and area captures; it is ignored for window captures.
    func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [SCWindow] = []) async throws -> CaptureResult {
        let config = SCScreenshotConfiguration()
        config.showsCursor = options.showsCursor
        config.dynamicRange = .sdr

        let filter: SCContentFilter
        let scale: CGFloat
        let pointSize: CGSize

        switch target {
        case .display(let display):
            filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
            scale = Self.scale(forDisplayID: display.displayID)
            pointSize = display.frame.size
        case .area(let rect, let display):
            filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
            scale = Self.scale(forDisplayID: display.displayID)
            config.sourceRect = Geometry.displayLocal(rect, in: display.frame)
            pointSize = rect.size
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.ignoreShadows = true
            scale = Self.scale(forDisplayID: Self.displayID(containing: window.frame))
            pointSize = window.frame.size
        }

        let pixels = Geometry.pixelSize(points: pointSize, scale: scale)
        config.width = pixels.width
        config.height = pixels.height

        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
        guard let image = output.sdrImage else { throw CaptureError.noImage }
        return CaptureResult(image: image, scale: scale, target: target)
    }

    /// Backing scale of a display: from its NSScreen when available, otherwise from the display
    /// mode's pixel width over its point width.
    static func scale(forDisplayID id: CGDirectDisplayID) -> CGFloat {
        if let screen = screen(forDisplayID: id) {
            return screen.backingScaleFactor
        }
        let bounds = CGDisplayBounds(id)
        guard bounds.width > 0, let mode = CGDisplayCopyDisplayMode(id) else { return 1 }
        return CGFloat(mode.pixelWidth) / bounds.width
    }

    static func screen(forDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == id
        }
    }

    /// The display containing the centre of `cgRect` (CG global coordinates), or the main display.
    static func displayID(containing cgRect: CGRect) -> CGDirectDisplayID {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: cgRect.midX, y: cgRect.midY), 1, &id, &count)
        return count > 0 ? id : CGMainDisplayID()
    }
}
```

- [ ] **Step 3: Add a debug fullscreen capture to the coordinator**

This version writes to the temporary directory and opens the result, so the capture path can be checked before the save pipeline exists. Task 7 replaces the debug output with the real pipeline.

`TidyShot/App/AppCoordinator.swift`:
```swift
import AppKit
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    private let permissionWindow = PermissionWindowController()
    private(set) var isCapturing = false

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    func start() {
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }

    func captureFullscreen() async {
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            debugOpen(result)
        }
    }

    /// Runs the engine and logs failures. Returns nil on failure.
    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = []) async -> CaptureResult? {
        do {
            return try await engine.capture(target, options: CaptureOptions(showsCursor: false), excludingWindows: excludingWindows)
        } catch {
            NSLog("Capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Debug output: encode, write to the temp directory, open in the default viewer.
    private func debugOpen(_ result: CaptureResult) {
        do {
            let png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("TidyShot-debug-\(Int(Date().timeIntervalSince1970))")
                .appendingPathExtension("png")
            try png.write(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("Debug write failed: \(error.localizedDescription)")
        }
    }

    /// Fetches shareable content, or shows the permission window and returns nil.
    func loadContent() async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            permissionWindow.show()
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

`TidyShot/App/MenuContent.swift`:
```swift
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
        Button("Capture Fullscreen") {
            Task { await coordinator.captureFullscreen() }
        }
        .disabled(coordinator.isCapturing)
        Divider()
        Button("Quit TidyShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

- [ ] **Step 4: Build and verify manually**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected: with ad-hoc signing, the permission window may reappear after a rebuild; grant access in System Settings and relaunch. Then choose "Capture Fullscreen" from the menu. Preview opens a PNG of the display under the cursor. Check in Preview's Tools > Show Inspector: pixel size equals the display's pixel resolution (for example 3024 × 1964 on a 14-inch MacBook Pro) and DPI is 144. The cursor is not in the image. On a two-display setup, move the cursor to the other display and repeat; the other display is captured.

- [ ] **Step 5: Commit**

```bash
git add TidyShot
git commit -m "feat: add ScreenCaptureKit capture engine with debug fullscreen capture"
```

---

### Task 7: Output pipeline: save folder, clipboard, notification, sound

**Files:**
- Create: `TidyShot/Output/SaveLocation.swift`
- Create: `TidyShot/Output/Pasteboard.swift`
- Create: `TidyShot/Output/Notifier.swift`
- Create: `TidyShot/Output/SoundPlayer.swift`
- Modify: `TidyShot/App/AppCoordinator.swift`
- Modify: `TidyShot/App/MenuContent.swift`

**Interfaces:**
- Consumes: `AppCoordinator.capture(_:excludingWindows:)`, `ImageEncoder.pngData`, `FileNamer`.
- Produces:
  - `SaveLocation` (`@Observable`): `private(set) var currentURL: URL?`, `func store(_ url: URL) throws`, `func chooseFolder() async -> URL?`, `func ensureFolder() async -> URL?`, `func write(_ data: Data, baseName: String, ext: String, in folder: URL) throws -> URL`
  - `Pasteboard.copy(image: CGImage, pngData: Data, scale: CGFloat)`
  - `Notifier`: `func setUp()`, `func notifySaved(fileURL: URL)`, `func notifyError(_ message: String)`
  - `SoundPlayer.playShutter()`
  - On `AppCoordinator`: `let saveLocation: SaveLocation`, `private(set) var lastCaptureURL: URL?`, `func revealLastCapture()`, `func save(_ result: CaptureResult, appName: String?) async`; `capture(_:excludingWindows:)` now posts a failure notification.

Sandbox notes: every file system call on the bookmarked folder, including the `fileExists` check that picks a unique name, must happen between `startAccessingSecurityScopedResource()` and `stopAccessingSecurityScopedResource()`. Refreshing a stale bookmark also needs that access. The image is copied to the clipboard before the folder is resolved, so a cancelled folder chooser never loses the capture.

- [ ] **Step 1: Write SaveLocation**

`TidyShot/Output/SaveLocation.swift`:
```swift
import AppKit
import Observation

/// The user-chosen save folder, persisted as a security-scoped bookmark (required under App Sandbox).
@Observable
final class SaveLocation {
    private static let bookmarkKey = "saveFolderBookmark"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var currentURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentURL = Self.resolveBookmark(from: defaults)
    }

    func store(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: Self.bookmarkKey)
        currentURL = url
    }

    /// Asks the user to pick a folder. Returns nil if cancelled.
    func chooseFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where TidyShot saves screenshots."
        panel.prompt = "Use This Folder"
        // Reached from a global hotkey while another app is active; a plain activate() can be
        // refused and the panel would open behind that app. Marked for future deprecation; no warning today.
        NSApplication.shared.activate(ignoringOtherApps: true)
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return nil }
        do {
            try store(url)
        } catch {
            NSLog("Could not store bookmark: \(error.localizedDescription)")
            return nil
        }
        return url
    }

    /// The stored folder, or a freshly chosen one.
    func ensureFolder() async -> URL? {
        if let currentURL { return currentURL }
        return await chooseFolder()
    }

    /// Writes `data` as `baseName.ext` (or `baseName 2.ext`, ...) inside `folder`, holding
    /// security-scoped access for both the uniqueness check and the write. Returns the file URL.
    func write(_ data: Data, baseName: String, ext: String, in folder: URL) throws -> URL {
        try withAccess(to: folder) {
            let url = FileNamer.uniqueURL(baseName: baseName, ext: ext, in: folder)
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    private func withAccess<T>(to folder: URL, _ body: () throws -> T) rethrows -> T {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    private static func resolveBookmark(from defaults: UserDefaults) -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }
}
```

- [ ] **Step 2: Write Pasteboard**

`TidyShot/Output/Pasteboard.swift`:
```swift
import AppKit

enum Pasteboard {
    /// Puts the image on the general pasteboard as PNG and TIFF. The TIFF rep's size is set in
    /// points so Retina images paste at their on-screen size.
    static func copy(image: CGImage, pngData: Data, scale: CGFloat) {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)

        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        if let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
```

- [ ] **Step 3: Write Notifier**

`TidyShot/Output/Notifier.swift`:
```swift
import AppKit
import UserNotifications

/// Posts "saved" and "failed" notifications. Clicking a saved notification reveals the file in Finder.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Read from the nonisolated delegate callbacks, so it must not be MainActor-isolated.
    nonisolated private static let pathKey = "path"
    private let center = UNUserNotificationCenter.current()

    func setUp() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Notification authorization failed: \(error.localizedDescription)") }
        }
    }

    func notifySaved(fileURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot saved"
        content.body = fileURL.lastPathComponent
        content.userInfo = [Self.pathKey: fileURL.path]
        post(content)
    }

    func notifyError(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Capture failed"
        content.body = message
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { NSLog("Notification failed: \(error.localizedDescription)") }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo[Self.pathKey] as? String else { return }
        let url = URL(fileURLWithPath: path)
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
```

- [ ] **Step 4: Write SoundPlayer**

`TidyShot/Output/SoundPlayer.swift`:
```swift
import AppKit

enum SoundPlayer {
    private static let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"
    private static let shutter = NSSound(contentsOfFile: shutterPath, byReference: true)

    /// Plays the system screenshot sound. Silent if the sound file is missing.
    static func playShutter() {
        shutter?.stop()
        shutter?.play()
    }
}
```

- [ ] **Step 5: Replace the debug output in the coordinator with the real pipeline**

`TidyShot/App/AppCoordinator.swift`:
```swift
import AppKit
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()

    private(set) var isCapturing = false
    private(set) var lastCaptureURL: URL?

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    func start() {
        notifier.setUp()
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
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

    func revealLastCapture() {
        guard let lastCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCaptureURL])
    }

    /// Runs the engine. On failure posts a notification and returns nil.
    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = []) async -> CaptureResult? {
        do {
            return try await engine.capture(target, options: CaptureOptions(showsCursor: false), excludingWindows: excludingWindows)
        } catch {
            NSLog("Capture failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return nil
        }
    }

    /// Encode, copy to clipboard, save, play sound, notify. The clipboard copy happens before the
    /// folder is resolved so a cancelled folder chooser never loses the image.
    func save(_ result: CaptureResult, appName: String?) async {
        do {
            let png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
            Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
            guard let folder = await saveLocation.ensureFolder() else {
                notifier.notifyError("Not saved: no folder was chosen. The image is on the clipboard.")
                return
            }
            let baseName = FileNamer().name(appName: appName, counter: 1)
            let url = try saveLocation.write(png, baseName: baseName, ext: "png", in: folder)
            SoundPlayer.playShutter()
            lastCaptureURL = url
            notifier.notifySaved(fileURL: url)
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
        }
    }

    /// Fetches shareable content, or shows the permission window and returns nil.
    func loadContent() async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            permissionWindow.show()
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

`TidyShot/App/MenuContent.swift`:
```swift
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
        Button("Capture Fullscreen") {
            Task { await coordinator.captureFullscreen() }
        }
        .disabled(coordinator.isCapturing)
        Divider()
        Button("Reveal Last Capture") {
            coordinator.revealLastCapture()
        }
        .disabled(coordinator.lastCaptureURL == nil)
        Divider()
        Button("Quit TidyShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

- [ ] **Step 6: Build and verify manually**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected, in order:
1. First "Capture Fullscreen": a folder chooser appears. Choose Desktop. A notification "Screenshot saved / Screenshot 2026-10-19 at HH.MM.SS.png" appears and the shutter sound plays.
2. The file exists on the Desktop with the display's full pixel size.
3. Paste into Notes or Slack: the image appears at its on-screen size, not double size.
4. Click the notification: Finder opens with the file selected.
5. Capture again: no folder chooser; a second file is written. Capture twice within the same second: the second is named `... 2.png`.
6. Quit and relaunch, capture twice within the same second: the second is still named `... 2.png` (uniqueness check works with a bookmark-resolved folder).
7. Quit, relaunch, delete the bookmark with `defaults delete io.tky.tidyshot saveFolderBookmark`, relaunch, capture, press Cancel in the folder chooser: a "Capture failed / Not saved: no folder was chosen" notification appears and the image is still on the clipboard.
8. "Reveal Last Capture" selects the newest file in Finder.

- [ ] **Step 7: Commit**

```bash
git add TidyShot
git commit -m "feat: save captures to a bookmarked folder, copy to clipboard, notify"
```

---

### Task 8: Settings and global hotkeys

**Files:**
- Create: `TidyShot/App/Shortcuts.swift`
- Create: `TidyShot/Settings/AppSettings.swift`
- Create: `TidyShot/Settings/SettingsView.swift`
- Create: `TidyShot/Settings/GeneralSettingsView.swift`
- Create: `TidyShot/Settings/ShortcutsSettingsView.swift`
- Create: `TidyShot/Settings/CaptureSettingsView.swift`
- Modify: `TidyShot/App/TidyShotApp.swift`
- Modify: `TidyShot/App/AppCoordinator.swift`
- Modify: `TidyShot/App/MenuContent.swift`

**Interfaces:**
- Produces:
  - `KeyboardShortcuts.Name.captureArea`, `.captureWindow`, `.captureFullscreen`
  - `AppSettings.shared` (`@Observable`): `showsCursor: Bool`, `copyImageToClipboard: Bool`, `showNotification: Bool`, `playSound: Bool`, `fileNameTemplate: String`, `func nextCounter() -> Int`
  - On `AppCoordinator`: `let settings: AppSettings`, `private func registerShortcuts()`
- Note: `KeyboardShortcuts.onKeyUp(for:)` for `.captureArea` and `.captureWindow` is registered in Tasks 9 and 10 when those methods exist. This task registers `.captureFullscreen` only.

- [ ] **Step 1: Define shortcut names**

`TidyShot/App/Shortcuts.swift`:
```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", initial: .init(.four, modifiers: [.control, .shift]))
    static let captureWindow = Self("captureWindow", initial: .init(.two, modifiers: [.control, .shift]))
    static let captureFullscreen = Self("captureFullscreen", initial: .init(.three, modifiers: [.control, .shift]))
}
```
`initial:` is the current parameter name in KeyboardShortcuts 3.x; `default:` still compiles but is deprecated.

- [ ] **Step 2: Write AppSettings**

`TidyShot/Settings/AppSettings.swift`:
```swift
import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let showsCursor = "showsCursor"
        static let copyImageToClipboard = "copyImageToClipboard"
        static let showNotification = "showNotification"
        static let playSound = "playSound"
        static let fileNameTemplate = "fileNameTemplate"
        static let counter = "captureCounter"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showsCursor: Bool { didSet { defaults.set(showsCursor, forKey: Keys.showsCursor) } }
    var copyImageToClipboard: Bool { didSet { defaults.set(copyImageToClipboard, forKey: Keys.copyImageToClipboard) } }
    var showNotification: Bool { didSet { defaults.set(showNotification, forKey: Keys.showNotification) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Keys.playSound) } }
    var fileNameTemplate: String { didSet { defaults.set(fileNameTemplate, forKey: Keys.fileNameTemplate) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.showsCursor: false,
            Keys.copyImageToClipboard: true,
            Keys.showNotification: true,
            Keys.playSound: true,
            Keys.fileNameTemplate: FileNamer.defaultTemplate,
        ])
        showsCursor = defaults.bool(forKey: Keys.showsCursor)
        copyImageToClipboard = defaults.bool(forKey: Keys.copyImageToClipboard)
        showNotification = defaults.bool(forKey: Keys.showNotification)
        playSound = defaults.bool(forKey: Keys.playSound)
        fileNameTemplate = defaults.string(forKey: Keys.fileNameTemplate) ?? FileNamer.defaultTemplate
    }

    /// Increments and returns the persistent capture counter used by the {counter} token.
    func nextCounter() -> Int {
        let next = defaults.integer(forKey: Keys.counter) + 1
        defaults.set(next, forKey: Keys.counter)
        return next
    }
}
```

- [ ] **Step 3: Write the settings views**

`TidyShot/Settings/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "camera") }
        }
        .frame(width: 500)
        .onAppear {
            NSApplication.shared.activate()
        }
    }
}
```

`TidyShot/Settings/GeneralSettingsView.swift`:
```swift
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    private let saveLocation = AppCoordinator.shared.saveLocation

    var body: some View {
        Form {
            LabeledContent("Save to") {
                HStack {
                    Text(saveLocation.currentURL?.path(percentEncoded: false) ?? "Not set")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…") {
                        Task { _ = await saveLocation.chooseFolder() }
                    }
                }
            }
            TextField("File name", text: $settings.fileNameTemplate)
            Text("Tokens: {date} {time} {datetime} {app} {counter} {random} {random:8}")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Copy image to clipboard", isOn: $settings.copyImageToClipboard)
            Toggle("Show notification", isOn: $settings.showNotification)
            Toggle("Play sound", isOn: $settings.playSound)
        }
        .formStyle(.grouped)
    }
}
```

`TidyShot/Settings/ShortcutsSettingsView.swift`:
```swift
import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Capture area:", name: .captureArea)
            KeyboardShortcuts.Recorder("Capture window:", name: .captureWindow)
            KeyboardShortcuts.Recorder("Capture fullscreen:", name: .captureFullscreen)
            Text("macOS reserves ⌘⇧3, ⌘⇧4 and ⌘⇧5. To use them here, disable them in System Settings > Keyboard > Keyboard Shortcuts > Screenshots.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
```

`TidyShot/Settings/CaptureSettingsView.swift`:
```swift
import SwiftUI

struct CaptureSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Show cursor in screenshots", isOn: $settings.showsCursor)
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 4: Add the Settings scene, menu item, and hotkey registration**

`TidyShot/App/TidyShotApp.swift`:
```swift
import SwiftUI

@main
struct TidyShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("TidyShot", systemImage: "camera.viewfinder") {
            MenuContent()
        }
        Settings {
            SettingsView()
        }
    }
}
```

`TidyShot/App/MenuContent.swift`:
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
        Button(menuTitle("Capture Fullscreen", .captureFullscreen)) {
            Task { await coordinator.captureFullscreen() }
        }
        .disabled(coordinator.isCapturing)
        Divider()
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

`TidyShot/App/AppCoordinator.swift` (full file; adds the import, `settings`, `registerShortcuts()`, and uses settings in `capture` and `save`):
```swift
import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    let settings = AppSettings.shared
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()

    private(set) var isCapturing = false
    private(set) var lastCaptureURL: URL?

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    func start() {
        notifier.setUp()
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

    /// Encode, copy to clipboard, save, play sound, notify. The clipboard copy happens before the
    /// folder is resolved so a cancelled folder chooser never loses the image.
    func save(_ result: CaptureResult, appName: String?) async {
        do {
            let png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
            if settings.copyImageToClipboard {
                Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
            }
            guard let folder = await saveLocation.ensureFolder() else {
                notifier.notifyError("Not saved: no folder was chosen.")
                return
            }
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: settings.nextCounter())
            let url = try saveLocation.write(png, baseName: baseName, ext: "png", in: folder)
            if settings.playSound {
                SoundPlayer.playShutter()
            }
            lastCaptureURL = url
            if settings.showNotification {
                notifier.notifySaved(fileURL: url)
            }
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
        }
    }

    /// Fetches shareable content, or shows the permission window and returns nil.
    func loadContent() async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            permissionWindow.show()
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

- [ ] **Step 5: Build, test, verify manually**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head && open .build/Build/Products/Debug/TidyShot.app
```
Expected: `Test run with 21 tests in 4 suites passed`. Then:
1. Press `⌃⇧3` with any app in front: a fullscreen capture is taken and saved.
2. Menu shows "Capture Fullscreen  ⌃⇧3".
3. "Settings…" opens a window with three tabs. In Shortcuts, record a different key for fullscreen; the menu title updates on next open and the new key works.
4. In General, change the template to `{app} {counter}` and capture from Safari: file is named like `Safari 7.png`.
5. Turn off "Play sound" and "Show notification": the next capture is silent.
6. In Capture, enable "Show cursor": the cursor appears in the next capture.

- [ ] **Step 6: Commit**

```bash
git add TidyShot
git commit -m "feat: add settings window and global fullscreen hotkey"
```

---

### Task 9: Area selection overlay

**Files:**
- Create: `TidyShot/Selection/Selection.swift`
- Create: `TidyShot/Selection/SelectionWindow.swift`
- Create: `TidyShot/Selection/SelectionView.swift`
- Create: `TidyShot/Selection/SelectionController.swift`
- Modify: `TidyShot/App/AppCoordinator.swift`
- Modify: `TidyShot/App/MenuContent.swift`

**Interfaces:**
- Consumes: `Geometry.cgRect(fromAppKit:primaryHeight:)`, `CaptureEngine.shareableContent()`, `CaptureTarget.area`, `AppCoordinator.capture(_:excludingWindows:)`, `AppCoordinator.save(_:appName:)`.
- Produces:
  - `enum SelectionMode { case area, window }`
  - `enum Selection { case area(rect: CGRect, display: SCDisplay); case window(SCWindow) }` (rect in CG global points)
  - `SelectionWindow(screen: NSScreen)` with `let displayID: CGDirectDisplayID`
  - `SelectionView`: `var mode: SelectionMode`, `var onComplete: ((CGRect) -> Void)?` (AppKit global rect), `var onCancel: (() -> Void)?`, `var onMouseMoved: ((CGPoint) -> Void)?` (AppKit global point), `var onPickWindow: (() -> Void)?`, `var highlightedRect: CGRect?` (view coords)
  - `SelectionController(engine: CaptureEngine)`: `func select(mode: SelectionMode, content: SCShareableContent) async -> Selection?`, `func overlayWindows() async -> [SCWindow]`, `func dismiss()`
  - On `AppCoordinator`: `func captureArea() async`, `private func runSelection(mode: SelectionMode) async`

Behaviour: one borderless window per screen at `.screenSaver` level dims the screen. Crosshair lines follow the cursor. Dragging draws a clear rectangle with a white border and a "W × H" label in points. Releasing resolves the selection. Escape cancels. A click without a drag cancels in this task; Task 10 turns it into a window pick.

The overlay stays on screen while the capture runs. The coordinator asks the controller for the overlay's own `SCWindow`s (a fresh `SCShareableContent` fetch filtered by this process id) and passes them to the engine's `excludingWindows`, so the dimming never appears in the output regardless of timing. `dismiss()` removes the overlay after the capture and before any save UI (the folder chooser must not appear under the overlay). Cancel dismisses immediately.

- [ ] **Step 1: Write the selection types**

`TidyShot/Selection/Selection.swift`:
```swift
import CoreGraphics
import ScreenCaptureKit

enum SelectionMode {
    case area
    case window
}

/// Result of the selection overlay. Rects are in CoreGraphics global points.
enum Selection {
    case area(rect: CGRect, display: SCDisplay)
    case window(SCWindow)
}
```

- [ ] **Step 2: Write the overlay window**

`TidyShot/Selection/SelectionWindow.swift`:
```swift
import AppKit

/// Transparent, borderless window covering one screen, above everything else.
final class SelectionWindow: NSWindow {
    /// CoreGraphics display id of the screen this window covers.
    let displayID: CGDirectDisplayID

    init(screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        displayID = number?.uint32Value ?? CGMainDisplayID()
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 3: Write the selection view**

`TidyShot/Selection/SelectionView.swift`:
```swift
import AppKit

/// Draws the dimmed overlay, crosshair, drag rectangle, size label, and window highlight.
/// All stored rects and points are in this view's coordinates (bottom-left origin).
final class SelectionView: NSView {
    var mode: SelectionMode = .area
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?
    var onPickWindow: (() -> Void)?

    /// Window frame under the cursor, set by the controller. Drawn as a clear hole with an accent border.
    var highlightedRect: CGRect? {
        didSet { if highlightedRect != oldValue { needsDisplay = true } }
    }

    private var dragStart: CGPoint?
    private var dragRect: CGRect?
    private var cursor: CGPoint?
    private var trackingArea: NSTrackingArea?

    private let dimColor = NSColor.black.withAlphaComponent(0.35)
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    /// Clicks on a non-key overlay window (another screen) must register as mouseDown, not just activate.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        needsDisplay = true
        if let window {
            let global = window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
            onMouseMoved?(global)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        dragRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y)).integral
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragRect = nil
            needsDisplay = true
        }
        if mode == .area, let rect = dragRect, rect.width >= 2, rect.height >= 2 {
            guard let window else {
                onCancel?()
                return
            }
            onComplete?(window.convertToScreen(convert(rect, to: nil)))
        } else if highlightedRect != nil {
            onPickWindow?()
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        dimColor.setFill()
        bounds.fill()

        let isDragging = mode == .area && dragStart != nil && dragRect != nil

        if isDragging, let rect = dragRect {
            punchHole(rect)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            drawSizeLabel(for: rect)
        } else if let highlight = highlightedRect {
            punchHole(highlight)
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: highlight.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
            drawSizeLabel(for: highlight)
        }

        if let cursor, !isDragging, mode == .area {
            drawCrosshair(at: cursor)
        }
    }

    private func punchHole(_ rect: CGRect) {
        NSColor.clear.setFill()
        rect.fill(using: .copy)
    }

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

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 12, height: 6)
        var origin = CGPoint(x: rect.minX, y: rect.minY - textSize.height - padding.height - 6)
        if origin.y < bounds.minY + 4 {
            origin.y = rect.maxY + 6
        }
        if origin.y + textSize.height + padding.height > bounds.maxY {
            origin.y = rect.minY + 6
        }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - textSize.width - padding.width - 4)
        let background = CGRect(origin: origin, size: CGSize(width: textSize.width + padding.width, height: textSize.height + padding.height))
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: origin.x + padding.width / 2, y: origin.y + padding.height / 2), withAttributes: attributes)
    }
}
```

- [ ] **Step 4: Write the controller**

`TidyShot/Selection/SelectionController.swift`:
```swift
import AppKit
import ScreenCaptureKit

/// Shows one SelectionWindow per screen and resolves to a Selection, or nil when cancelled.
/// On success the overlay stays up until `dismiss()` so the capture can exclude it by window.
final class SelectionController {
    private let engine: CaptureEngine
    private var windows: [SelectionWindow] = []
    private var views: [SelectionView] = []
    private var continuation: CheckedContinuation<Selection?, Never>?
    private var displays: [SCDisplay] = []

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    func select(mode: SelectionMode, content: SCShareableContent) async -> Selection? {
        guard continuation == nil, !NSScreen.screens.isEmpty else { return nil }
        displays = content.displays

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.mode = mode
            // Callbacks hop to the next run-loop turn so the view is never torn down inside its own event handler.
            view.onComplete = { [weak self] appKitRect in Task { self?.finishArea(appKitRect) } }
            view.onCancel = { [weak self] in Task { self?.finish(nil) } }
            window.contentView = view
            window.makeFirstResponder(view)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            views.append(view)
        }

        // Called from a global hotkey while another app is active; cooperative activation can refuse
        // a plain activate(), and without activation the overlay never becomes key and Escape is lost.
        // activate(ignoringOtherApps:) is marked for future deprecation in the SDK; it compiles without a warning today.
        NSApplication.shared.activate(ignoringOtherApps: true)
        windows.first { $0.frame.contains(NSEvent.mouseLocation) }?.makeKey()

        return await withCheckedContinuation { continuation = $0 }
    }

    /// This process's on-screen windows as ScreenCaptureKit sees them, for `excludingWindows`.
    /// ScreenCaptureKit can lag a frame behind the window server, so retry briefly until every
    /// overlay window is listed. Returns whatever was found after the last attempt.
    func overlayWindows() async -> [SCWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var found: [SCWindow] = []
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let fresh = try? await engine.shareableContent() else { continue }
            found = fresh.windows.filter { $0.owningApplication?.processID == selfPID }
            if found.count >= windows.count { break }
        }
        return found
    }

    /// Removes the overlay. Safe to call more than once.
    func dismiss() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        views = []
        displays = []
    }

    private func finishArea(_ appKitRect: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgRect = Geometry.cgRect(fromAppKit: appKitRect, primaryHeight: primaryHeight)
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

    /// Resumes the waiting caller. Cancel dismisses the overlay at once; success leaves it up.
    private func finish(_ selection: Selection?) {
        guard let continuation else { return }
        self.continuation = nil
        if selection == nil {
            dismiss()
        }
        continuation.resume(returning: selection)
    }
}
```

- [ ] **Step 5: Wire area capture into the coordinator and menu**

`TidyShot/App/AppCoordinator.swift` (full file; adds `selector`, `captureArea()`, `runSelection(mode:)`, and the `.captureArea` hotkey):
```swift
import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    let settings = AppSettings.shared
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)

    private(set) var isCapturing = false
    private(set) var lastCaptureURL: URL?

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    func start() {
        notifier.setUp()
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

    /// Encode, copy to clipboard, save, play sound, notify. The clipboard copy happens before the
    /// folder is resolved so a cancelled folder chooser never loses the image.
    func save(_ result: CaptureResult, appName: String?) async {
        do {
            let png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
            if settings.copyImageToClipboard {
                Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
            }
            guard let folder = await saveLocation.ensureFolder() else {
                notifier.notifyError("Not saved: no folder was chosen.")
                return
            }
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: settings.nextCounter())
            let url = try saveLocation.write(png, baseName: baseName, ext: "png", in: folder)
            if settings.playSound {
                SoundPlayer.playShutter()
            }
            lastCaptureURL = url
            if settings.showNotification {
                notifier.notifySaved(fileURL: url)
            }
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
        }
    }

    /// Fetches shareable content, or shows the permission window and returns nil.
    func loadContent() async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            permissionWindow.show()
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

In `TidyShot/App/MenuContent.swift`, add a "Capture Area" button above "Capture Fullscreen":
```swift
        Button(menuTitle("Capture Area", .captureArea)) {
            Task { await coordinator.captureArea() }
        }
        .disabled(coordinator.isCapturing)
```

- [ ] **Step 6: Build and verify manually**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected:
1. With Safari frontmost, press `⌃⇧4`: every screen dims, the cursor becomes a crosshair with full-screen guide lines.
2. Press Escape immediately (no click first): overlay disappears, nothing saved.
3. Press `⌃⇧4`, drag: the rectangle clears to show the content underneath, with a white border and a "W × H" label below it (above it when near the bottom edge).
4. Release: the overlay stays for a moment, then disappears; shutter sound; notification. The saved PNG has exactly `W*scale × H*scale` pixels and no dimming or crosshair in it.
5. Click without dragging on the desktop: overlay disappears, nothing saved.
6. With two displays: press `⌃⇧4` with the cursor on display A, move to display B, drag there. The capture comes from display B with the right content.
7. Press `⌃⇧4` twice quickly: only one overlay appears.
8. Delete the save bookmark (`defaults delete io.tky.tidyshot saveFolderBookmark`), relaunch, `⌃⇧4` and drag: the folder chooser appears on top, not under a dimmed screen.

- [ ] **Step 7: Commit**

```bash
git add TidyShot
git commit -m "feat: add area selection overlay"
```

---

### Task 10: Window picking

**Files:**
- Create: `TidyShot/Selection/WindowPicker.swift`
- Create: `TidyShotTests/WindowPickerTests.swift`
- Modify: `TidyShot/Selection/SelectionController.swift`
- Modify: `TidyShot/App/AppCoordinator.swift`
- Modify: `TidyShot/App/MenuContent.swift`

**Interfaces:**
- Consumes: `SelectionView.onMouseMoved`, `SelectionView.onPickWindow`, `SelectionView.highlightedRect`, `Geometry.cgPoint`, `Geometry.appKitRect`.
- Note: `overlayWindows()` excludes every TidyShot window by process id, so the Settings window cannot be area-captured in this phase. Acceptable; a later phase can match on `windowID` instead.
- Produces:
  - `WindowPicker(content: SCShareableContent, selfPID: pid_t)`, `func window(at cgPoint: CGPoint) -> SCWindow?`
  - `WindowPicker.isPickable(isOnScreen: Bool, layer: Int, frame: CGRect, ownerPID: pid_t?, selfPID: pid_t) -> Bool`
  - On `AppCoordinator`: `func captureWindow() async`

Behaviour: in both modes, when the cursor is not dragging, the topmost normal-level window under the cursor (not owned by TidyShot) is highlighted with an accent border. A click captures it. In `.window` mode dragging draws nothing. `SCShareableContent.windows` is ordered front to back in practice (Apple does not document the order, and `SCWindow` has no z-order property); the manual checklist verifies that overlapping windows resolve to the frontmost one.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/WindowPickerTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct WindowPickerTests {
    let frame = CGRect(x: 0, y: 0, width: 800, height: 600)

    @Test func normalOnScreenWindowFromAnotherAppIsPickable() {
        #expect(WindowPicker.isPickable(isOnScreen: true, layer: 0, frame: frame, ownerPID: 100, selfPID: 42))
    }

    @Test func ownWindowsAreNotPickable() {
        #expect(!WindowPicker.isPickable(isOnScreen: true, layer: 0, frame: frame, ownerPID: 42, selfPID: 42))
    }

    @Test func offScreenWindowIsNotPickable() {
        #expect(!WindowPicker.isPickable(isOnScreen: false, layer: 0, frame: frame, ownerPID: 100, selfPID: 42))
    }

    @Test func nonZeroLayerIsNotPickable() {
        #expect(!WindowPicker.isPickable(isOnScreen: true, layer: 25, frame: frame, ownerPID: 100, selfPID: 42))
    }

    @Test func tinyWindowIsNotPickable() {
        let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(!WindowPicker.isPickable(isOnScreen: true, layer: 0, frame: tiny, ownerPID: 100, selfPID: 42))
    }

    @Test func unknownOwnerIsPickable() {
        #expect(WindowPicker.isPickable(isOnScreen: true, layer: 0, frame: frame, ownerPID: nil, selfPID: 42))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'WindowPicker' in scope`.

- [ ] **Step 3: Implement WindowPicker**

`TidyShot/Selection/WindowPicker.swift`:
```swift
import Foundation
import ScreenCaptureKit

/// Finds the window under a point. Windows come from ScreenCaptureKit ordered front to back.
struct WindowPicker {
    let windows: [SCWindow]

    init(content: SCShareableContent, selfPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        windows = content.windows.filter { window in
            Self.isPickable(isOnScreen: window.isOnScreen,
                            layer: window.windowLayer,
                            frame: window.frame,
                            ownerPID: window.owningApplication?.processID,
                            selfPID: selfPID)
        }
    }

    /// Normal-level (layer 0), on-screen, at least 20 × 20 points, and not owned by this process.
    static func isPickable(isOnScreen: Bool, layer: Int, frame: CGRect, ownerPID: pid_t?, selfPID: pid_t) -> Bool {
        guard isOnScreen, layer == 0 else { return false }
        guard frame.width >= 20, frame.height >= 20 else { return false }
        if let ownerPID, ownerPID == selfPID { return false }
        return true
    }

    /// `cgPoint` is in CoreGraphics global coordinates.
    func window(at cgPoint: CGPoint) -> SCWindow? {
        windows.first { $0.frame.contains(cgPoint) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: `Test run with 27 tests in 5 suites passed`.

- [ ] **Step 5: Add hover highlighting and click-to-pick to the controller**

`TidyShot/Selection/SelectionController.swift` (full file):
```swift
import AppKit
import ScreenCaptureKit

/// Shows one SelectionWindow per screen and resolves to a Selection, or nil when cancelled.
/// On success the overlay stays up until `dismiss()` so the capture can exclude it by window.
final class SelectionController {
    private let engine: CaptureEngine
    private var windows: [SelectionWindow] = []
    private var views: [SelectionView] = []
    private var continuation: CheckedContinuation<Selection?, Never>?
    private var displays: [SCDisplay] = []
    private var picker: WindowPicker?
    private var hoveredWindow: SCWindow?

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    func select(mode: SelectionMode, content: SCShareableContent) async -> Selection? {
        guard continuation == nil, !NSScreen.screens.isEmpty else { return nil }
        displays = content.displays
        picker = WindowPicker(content: content)

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.mode = mode
            // Callbacks hop to the next run-loop turn so the view is never torn down inside its own event handler.
            view.onComplete = { [weak self] appKitRect in Task { self?.finishArea(appKitRect) } }
            view.onCancel = { [weak self] in Task { self?.finish(nil) } }
            view.onMouseMoved = { [weak self] globalPoint in self?.updateHover(at: globalPoint) }
            // Capture the hovered window now; a mouseMoved could change it before the Task runs.
            view.onPickWindow = { [weak self] in
                let picked = self?.hoveredWindow
                Task { self?.finish(picked.map(Selection.window)) }
            }
            window.contentView = view
            window.makeFirstResponder(view)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            views.append(view)
        }

        // Called from a global hotkey while another app is active; cooperative activation can refuse
        // a plain activate(), and without activation the overlay never becomes key and Escape is lost.
        // activate(ignoringOtherApps:) is marked for future deprecation in the SDK; it compiles without a warning today.
        NSApplication.shared.activate(ignoringOtherApps: true)
        windows.first { $0.frame.contains(NSEvent.mouseLocation) }?.makeKey()
        updateHover(at: NSEvent.mouseLocation)

        return await withCheckedContinuation { continuation = $0 }
    }

    /// This process's on-screen windows as ScreenCaptureKit sees them, for `excludingWindows`.
    /// ScreenCaptureKit can lag a frame behind the window server, so retry briefly until every
    /// overlay window is listed. Returns whatever was found after the last attempt.
    func overlayWindows() async -> [SCWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var found: [SCWindow] = []
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let fresh = try? await engine.shareableContent() else { continue }
            found = fresh.windows.filter { $0.owningApplication?.processID == selfPID }
            if found.count >= windows.count { break }
        }
        return found
    }

    /// Removes the overlay. Safe to call more than once.
    func dismiss() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        views = []
        displays = []
        picker = nil
        hoveredWindow = nil
    }

    /// `globalPoint` is in AppKit global coordinates.
    private func updateHover(at globalPoint: CGPoint) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = Geometry.cgPoint(fromAppKit: globalPoint, primaryHeight: primaryHeight)
        hoveredWindow = picker?.window(at: cgPoint)

        let appKitFrame = hoveredWindow.map { Geometry.appKitRect(fromCG: $0.frame, primaryHeight: primaryHeight) }
        for (window, view) in zip(windows, views) {
            guard let appKitFrame, window.frame.intersects(appKitFrame) else {
                view.highlightedRect = nil
                continue
            }
            let inWindow = window.convertFromScreen(appKitFrame)
            view.highlightedRect = view.convert(inWindow, from: nil).intersection(view.bounds)
        }
    }

    private func finishArea(_ appKitRect: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgRect = Geometry.cgRect(fromAppKit: appKitRect, primaryHeight: primaryHeight)
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

    /// Resumes the waiting caller. Cancel dismisses the overlay at once; success leaves it up.
    private func finish(_ selection: Selection?) {
        guard let continuation else { return }
        self.continuation = nil
        if selection == nil {
            dismiss()
        }
        continuation.resume(returning: selection)
    }
}
```

- [ ] **Step 6: Add window capture to the coordinator and menu**

In `TidyShot/App/AppCoordinator.swift`, add after `captureArea()`:
```swift
    func captureWindow() async {
        await runSelection(mode: .window)
    }
```
and in `registerShortcuts()` add:
```swift
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in
            Task { await self?.captureWindow() }
        }
```

In `TidyShot/App/MenuContent.swift`, add between "Capture Area" and "Capture Fullscreen":
```swift
        Button(menuTitle("Capture Window", .captureWindow)) {
            Task { await coordinator.captureWindow() }
        }
        .disabled(coordinator.isCapturing)
```

- [ ] **Step 7: Build and verify manually**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected:
1. Press `⌃⇧2`: the window under the cursor gets a clear hole with an accent border and its size label. Moving over another window moves the highlight. Over the desktop: no highlight.
2. Click: the overlay disappears and the window is saved. The PNG contains only the window (no shadow, no neighbours), with pixel size equal to the window's point size times the scale.
3. The file name's `{app}` token is the window's app name (set the template to `{app} {counter}` to check).
4. In area mode (`⌃⇧4`) hovering a window also highlights it; a click (no drag) captures that window; a drag still captures the rectangle.
5. Overlapping windows: the frontmost one under the cursor is highlighted and captured.
6. A window spanning two displays highlights on both overlays.
7. In window mode, dragging draws no rectangle; releasing over a window captures it.
8. Escape cancels in window mode.

- [ ] **Step 8: Commit**

```bash
git add TidyShot TidyShotTests
git commit -m "feat: add window picking to the selection overlay"
```

---

### Task 11: Magnifier loupe

**Files:**
- Modify: `TidyShot/Selection/SelectionView.swift`
- Modify: `TidyShot/Selection/SelectionController.swift`

**Interfaces:**
- Consumes: `CaptureEngine.capture(_:options:excludingWindows:)`, `SelectionController.overlayWindows()`, `SelectionWindow.displayID`.
- Produces on `SelectionView`: `var snapshot: CGImage?`, `var snapshotScale: CGFloat`.

Behaviour: once the overlay is up in area mode, the controller takes one screenshot per display with the overlay windows excluded and hands each view its display's image. The view draws a 128-point circular loupe near the cursor at 8x with a centre crosshair. Until the snapshot arrives the loupe is not drawn. At screen edges the visible part of the source region is drawn in its correct position inside the circle and the rest is black, so the centre crosshair always marks the cursor pixel. This snapshot is also the basis for the later freeze-screen feature.

- [ ] **Step 1: Add the loupe to SelectionView**

Add these properties to `SelectionView` after `highlightedRect`:
```swift
    /// Screenshot of this view's display, in pixels, used by the loupe.
    var snapshot: CGImage? {
        didSet { needsDisplay = true }
    }
    var snapshotScale: CGFloat = 2
```

Add this call at the end of `draw(_:)`, after the crosshair:
```swift
        if let cursor, mode == .area {
            drawLoupe(at: cursor)
        }
```

Add this method after `drawSizeLabel(for:)`:
```swift
    private func drawLoupe(at point: CGPoint) {
        guard let snapshot, let context = NSGraphicsContext.current?.cgContext else { return }
        let regionPoints: CGFloat = 16
        let zoom: CGFloat = 8
        let diameter = regionPoints * zoom
        let pixelsToPoints = zoom / snapshotScale

        // Source region in snapshot pixels. CGImage rows run top to bottom; the view's y runs bottom to top.
        let half = regionPoints * snapshotScale / 2
        let centreX = point.x * snapshotScale
        let centreY = (bounds.height - point.y) * snapshotScale
        let source = CGRect(x: centreX - half, y: centreY - half, width: half * 2, height: half * 2)
        let imageRect = CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
        let visible = source.intersection(imageRect)
        guard !visible.isEmpty, let cropped = snapshot.cropping(to: visible) else { return }

        var origin = CGPoint(x: point.x + 24, y: point.y - 24 - diameter)
        if origin.x + diameter > bounds.maxX { origin.x = point.x - 24 - diameter }
        if origin.y < bounds.minY { origin.y = point.y + 24 }
        let destination = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))

        // Where the visible part lands inside the circle. Image y is flipped relative to the view.
        let drawRect = CGRect(x: destination.minX + (visible.minX - source.minX) * pixelsToPoints,
                              y: destination.minY + (source.maxY - visible.maxY) * pixelsToPoints,
                              width: visible.width * pixelsToPoints,
                              height: visible.height * pixelsToPoints)

        context.saveGState()
        context.addEllipse(in: destination)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(destination)
        context.interpolationQuality = .none
        context.draw(cropped, in: drawRect)
        context.restoreGState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1
        cross.move(to: CGPoint(x: destination.minX, y: destination.midY + 0.5))
        cross.line(to: CGPoint(x: destination.maxX, y: destination.midY + 0.5))
        cross.move(to: CGPoint(x: destination.midX + 0.5, y: destination.minY))
        cross.line(to: CGPoint(x: destination.midX + 0.5, y: destination.maxY))
        cross.stroke()

        let ring = NSBezierPath(ovalIn: destination.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 2
        NSColor.white.setStroke()
        ring.stroke()
    }
```

- [ ] **Step 2: Take snapshots from the controller**

In `TidyShot/Selection/SelectionController.swift`:

Add a property after `hoveredWindow`:
```swift
    private var snapshotTask: Task<Void, Never>?
```

In `select(mode:content:)`, after `updateHover(at: NSEvent.mouseLocation)` and before `return await withCheckedContinuation`, add:
```swift
        if mode == .area {
            snapshotTask = Task { await takeSnapshots() }
        }
```

Add this method after `overlayWindows()`:
```swift
    /// One screenshot per display with our overlay excluded, delivered to the view on that display.
    private func takeSnapshots() async {
        let overlays = await overlayWindows()
        // A snapshot taken without every overlay excluded would show the dimming in the loupe; skip instead.
        guard overlays.count >= windows.count else { return }
        for display in displays {
            guard !Task.isCancelled else { return }
            guard let index = windows.firstIndex(where: { $0.displayID == display.displayID }) else { continue }
            guard let result = try? await engine.capture(.display(display),
                                                         options: CaptureOptions(showsCursor: false),
                                                         excludingWindows: overlays) else { continue }
            guard !Task.isCancelled, index < views.count else { return }
            views[index].snapshotScale = result.scale
            views[index].snapshot = result.image
        }
    }
```

In `dismiss()`, add as the first two lines:
```swift
        snapshotTask?.cancel()
        snapshotTask = nil
```

- [ ] **Step 3: Build and verify manually**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected:
1. Press `⌃⇧4`: within about 200 ms a round loupe appears to the lower right of the cursor showing the pixels under it at 8x, with a crosshair. Individual pixels are visible as sharp squares (no smoothing).
2. Move to the right or bottom edge: the loupe flips to the other side and stays on screen.
3. Put the cursor in the top-left corner of the screen: the loupe shows the corner pixels in the lower-right quadrant of the circle with black above and to the left; the crosshair centre is the corner pixel.
4. The loupe shows the real screen content, not the dimmed overlay.
5. Drag: the loupe follows the cursor during the drag.
6. `⌃⇧2` (window mode): no loupe.
7. Two displays: each display's loupe shows its own content.
8. Press Escape before the loupe appears: no crash, nothing saved.

- [ ] **Step 4: Commit**

```bash
git add TidyShot
git commit -m "feat: add magnifier loupe to area selection"
```

---

### Task 12: Final wiring, README, and manual test checklist

**Files:**
- Create: `README.md`
- Create: `docs/testing/phase-1-manual-checklist.md`
- Modify: `TidyShot/App/AppDelegate.swift`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Keep the app running after the last window closes**

`TidyShot/App/AppDelegate.swift`:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when this process is the unit-test host; the coordinator must not start then.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppCoordinator.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
```

- [ ] **Step 2: Write the README**

`README.md`:
````markdown
# TidyShot

A macOS menu bar screenshot tool. Capture an area, a window, or a display; it is saved as a
Retina-correct PNG, copied to the clipboard, and (in a later phase) uploaded to your own S3 bucket
with the URL on your clipboard.

Requires macOS 26 or later.

## Build

```bash
brew install xcodegen
xcodebuild -runFirstLaunch
cp Config/Local.xcconfig.example Config/Local.xcconfig
xcodegen generate
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/TidyShot.app
```

Or open `TidyShot.xcodeproj` in Xcode after `xcodegen generate`.

## Test

```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test
```

## Permissions

TidyShot needs Screen Recording permission (System Settings > Privacy & Security > Screen & System
Audio Recording). With ad-hoc signing (the default in `Config/Local.xcconfig.example`), macOS asks
again after every rebuild. Sign in to Xcode with an Apple ID and set `DEVELOPMENT_TEAM` in
`Config/Local.xcconfig` to avoid that.

## Default shortcuts

| Action | Shortcut |
|---|---|
| Capture area (click a window to capture it) | ⌃⇧4 |
| Capture window | ⌃⇧2 |
| Capture fullscreen | ⌃⇧3 |

Change them in Settings > Shortcuts.

## Documents

- Design: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`
- Plans: `docs/superpowers/plans/`
- Manual test checklist: `docs/testing/phase-1-manual-checklist.md`
````

- [ ] **Step 3: Write the manual test checklist**

`docs/testing/phase-1-manual-checklist.md`:
```markdown
# Phase 1 manual test checklist

Run after any change to Capture, Selection, or Output. Automated tests cover geometry, naming,
encoding, and window filtering; everything here needs eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, default settings.

## Permission
- [ ] Revoke Screen Recording in System Settings, relaunch: permission window appears, menu shows the permission item.
- [ ] Grant it: window turns green within a second; relaunch clears the window and menu item.

## Fullscreen (⌃⇧3)
- [ ] Captures the display under the cursor, at full pixel resolution, 144 DPI on Retina.
- [ ] Cursor absent by default; present when "Show cursor" is on.

## Area (⌃⇧4)
- [ ] Dim, crosshair, loupe appear on all displays, with Safari frontmost before the hotkey.
- [ ] Escape before any click cancels.
- [ ] Drag shows a clear rectangle, white border, "W × H" label; label flips above when near the bottom.
- [ ] Release saves `W*scale × H*scale` pixels with no dimming, crosshair, or loupe in the image.
- [ ] Click on the desktop cancels. Click on a window captures that window.
- [ ] Hotkey on display A, move to display B, drag there: capture comes from display B.
- [ ] Loupe at a screen corner shows black outside the screen and keeps the crosshair on the cursor pixel.
- [ ] Pressing the shortcut while the overlay is up does nothing extra.
- [ ] With no save folder set, the folder chooser appears above the screen, not under a dim overlay.

## Window (⌃⇧2)
- [ ] Hover highlights the frontmost window under the cursor; desktop gives no highlight.
- [ ] Two overlapping windows: the one in front is highlighted and captured.
- [ ] Click saves the window alone, no shadow, correct pixel size.
- [ ] Dragging draws nothing; release over a window captures it.
- [ ] `{app}` resolves to the window's app.
- [ ] Escape cancels.

## Output
- [ ] File lands in the chosen folder with the template name; same-second captures get " 2", also after a relaunch.
- [ ] Paste into Notes shows the image at point size, not double.
- [ ] Notification appears; clicking it reveals the file in Finder.
- [ ] Cancelling the folder chooser leaves the image on the clipboard and shows a "Not saved" notification.
- [ ] Shutter sound plays; toggles for sound, notification, and clipboard are honoured.
- [ ] Quit and relaunch: save folder remembered, counter continues.

## Settings
- [ ] Rebinding a shortcut takes effect immediately and shows in the menu.
- [ ] Choose… changes the folder and the next capture lands there.
```

- [ ] **Step 4: Run the full checklist and the unit tests**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test -quiet 2>&1 | grep -E "error:|Test run" | head
```
Expected: `Test run with 27 tests in 5 suites passed`. Then work through `docs/testing/phase-1-manual-checklist.md` and tick every box. Fix anything that fails before committing.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/testing TidyShot/App/AppDelegate.swift
git commit -m "docs: add README and Phase 1 manual test checklist"
```

---

## Out of scope for this plan (next plans)

- Phase 2: S3 upload, SigV4 signer, Keychain credentials, URL on clipboard, Quick Access Overlay, capture history and retry.
- Phase 3: full overlay actions, All-in-One mode, capture previous area, freeze screen (reuses the Task 11 snapshot), self-timer, window shadow and background options, pin to screen, URL scheme.
