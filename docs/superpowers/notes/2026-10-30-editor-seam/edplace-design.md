# `EDPLACE`: the editor window's placement seam, as built in the CT-2 design review

Kept from the CT-2 design's "constructed" angle (one of three seam designs the design review judged; design call 1
and call 10 in `docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`). CT-2 took the coordinator seam
alone (`EditorPresenting`, `makeEditor`); the window's own seam here, `EditorWindowPlacement`, is deferred as
`EDPLACE` and is the next editor seam. The three sections below keep their numbers from that document, since
`tests-editor.md` cites them by number: 2.1 is the `EditorWindowController.swift` diff (its `EditorPresenting`
part is CT-2's in the design's own form, spec section 2.1; the placement part is `EDPLACE`'s), 4 the fakes as that
angle built them (its `FakeEditor` differs from CT-2's, spec 3.1; `FakeEditorActions` and `EditorWindowPlacement.fixed()`
are `EDPLACE`'s), and 8 the controller-alone tests. All of it was built and run in a scratch copy of the tree at
a079a6f: `Test run with 2283 tests in 193 suites passed`, ten iterations of the two new suites green. Nothing here is
in the app or the suite yet. Abbreviations: `EWC` = `TidyShot/Editor/Window/EditorWindowController.swift`,
`+Editor` = `TidyShot/App/AppCoordinator+Editor.swift`, `Coord` = `TidyShot/App/AppCoordinator.swift`, `Env` =
`TidyShot/App/AppEnvironment.swift`, `Toolbar` = `TidyShot/Editor/Window/EditorToolbar.swift`, `World` =
`TidyShotTests/Support/CoordinatorWorld.swift`, `Fakes` = `TidyShotTests/Support/CoordinatorFakes.swift`. Line
numbers are at a079a6f unless a line says "after".

### 2.1 `TidyShot/Editor/Window/EditorWindowController.swift`

The protocol and the placement go after `EditorActions` (EWC:32); the controller's `onClose` changes type, the
init takes the placement, and three reads go through it; the conformance is an empty extension at the end.

```diff
--- a/TidyShot/Editor/Window/EditorWindowController.swift
+++ b/TidyShot/Editor/Window/EditorWindowController.swift
@@ -31,6 +31,47 @@
     var unusableBackgroundImage: (_ fileName: String) -> Void
 }
 
+/// What the coordinator asks of an open editor (editor seam): its model, coming forward, the record's
+/// state, the unsaved-changes sheet at a quit, and the call when it closes. The app's editor is
+/// `EditorWindowController`; the suite's is `FakeEditor`.
+protocol EditorPresenting: AnyObject {
+    var model: EditorModel { get }
+    /// Called from the editor's close; AppCoordinator drops the editor from its registry.
+    var onClose: ((any EditorPresenting) -> Void)? { get set }
+    func present()
+    func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool)
+    func askToSaveBeforeClosing() async -> Bool
+}
+
+/// What an editor window reads from the screens and the workspace (editor seam): the visible frame
+/// it is sized and placed in, the display under it for a desktop-picture background, and where a
+/// Space change is posted. The app's editors use `.live`; the suite passes a fixed frame, no display
+/// and a notification centre of its own, so a controller it builds reads no screen and registers
+/// nothing with NSWorkspace.
+struct EditorWindowPlacement {
+    /// The visible frame of the screen the window opens on, read once while it is placed.
+    var visibleFrame: () -> NSRect
+    /// The display under the window, nil while it is off screen.
+    var displayID: (NSWindow?) -> CGDirectDisplayID?
+    /// Where `NSWorkspace.activeSpaceDidChangeNotification` is posted.
+    var spaceChanges: NotificationCenter
+
+    /// The screen under the mouse (else the main screen, else the first), the window's own screen,
+    /// and the workspace's notification centre.
+    static var live: EditorWindowPlacement {
+        EditorWindowPlacement(
+            visibleFrame: {
+                let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
+                    ?? NSScreen.main ?? NSScreen.screens[0]
+                return screen.visibleFrame
+            },
+            displayID: { window in
+                (window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
+            },
+            spaceChanges: NSWorkspace.shared.notificationCenter)
+    }
+}
+
 /// One annotation editor window for one capture record: the window, the two stacked views, the
 /// document actions, zoom, and the unsaved-changes sheet.
 final class EditorWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations {
@@ -38,9 +79,10 @@
     let canvasView: CanvasView
     private let baseView: BaseImageView
     /// Called from `windowWillClose(_:)`; AppCoordinator drops the editor from its registry.
-    var onClose: ((EditorWindowController) -> Void)?
+    var onClose: ((any EditorPresenting) -> Void)?
 
     private let actions: EditorActions
+    private let placement: EditorWindowPlacement
     /// The toolbar's popovers (EditorToolbar.swift), kept so only one is shown at a time.
     var colorPopover: NSPopover?
     var optionsPopover: NSPopover?
@@ -64,9 +106,11 @@
     private static var loggedMainMenu = false
     #endif
 
-    init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, cascadeFrom: NSWindow?) {
+    init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, cascadeFrom: NSWindow?,
+         placement: EditorWindowPlacement = .live) {
         self.model = model
         self.actions = actions
+        self.placement = placement
         let baseView = BaseImageView(frame: .zero)
         baseView.image = model.base
         self.baseView = baseView
@@ -100,7 +144,7 @@
         placeWindow(cascadeFrom: cascadeFrom)
         observeEdited()
         observeBackgroundFill()
-        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
+        spaceObserver = placement.spaceChanges.addObserver(
             forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
             MainActor.assumeIsolated { self?.refreshDesktopPicture() }
         }
@@ -120,8 +164,7 @@
         guard let window, let content = window.contentView else { return }
         let minimumWidth = minimumToolbarContentWidth()
         window.contentMinSize.width = minimumWidth
-        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
-        let visible = screen.visibleFrame
+        let visible = placement.visibleFrame()
         let chrome = CGSize(width: window.frame.width - content.frame.width,
                             height: window.frame.height - content.frame.height)
         let contentSize = EditorWindowGeometry.initialContentSize(
@@ -319,7 +362,7 @@
     /// The display under the editor window, whose wallpaper a desktop-picture background uses;
     /// nil (the main display) while the window is off screen.
     var displayID: CGDirectDisplayID? {
-        (window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
+        placement.displayID(window)
     }
 
     // MARK: Background preview
@@ -497,7 +540,7 @@
 
     func windowWillClose(_ notification: Notification) {
         if let spaceObserver {
-            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
+            placement.spaceChanges.removeObserver(spaceObserver)
             self.spaceObserver = nil
         }
         onClose?(self)
@@ -519,3 +562,5 @@
         canvasView.endSpacePan()
     }
 }
+
+extension EditorWindowController: EditorPresenting {}
```

Why `onClose` is on the protocol and changes type (one token at EWC:41) rather than staying
`((EditorWindowController) -> Void)?`: a protocol property requirement must match the type exactly, and the fake has
to hand the coordinator something of the registry's element type. The alternative that leaves EWC:41 alone is a
fifth factory argument (`onClose: @escaping (any EditorPresenting) -> Void`) that the live closure wires with
`controller.onClose = { onClose($0) }`; it costs a longer factory and moves the `onClose` line out of
`presentEditor`. This angle takes the type change, since it changes the controller anyway (call C1).


## 4. The fakes (TidyShotTests/Support)

### 4.1 New file `TidyShotTests/Support/EditorFakes.swift` (full, as built)

```swift
import AppKit
import Foundation
import Testing
@testable import TidyShot

/// The editor in the suite (editor seam): what the coordinator handed it (the model, the actions, the
/// title and the proxy icon's file), every present and every push in order, and the quit's close sheet
/// answered from `answers` (true, Don't Save, when they run out) or held until `answer(_:)` while
/// `holds` is set. A held sheet whose task is cancelled answers Cancel, so a suite's time limit can end
/// it; a second sheet while one is held is recorded as an issue and answered Cancel at once.
///
/// Built with a window (`CoordinatorWorld.editorsHaveWindows`), it also owns a real
/// `EditorWindowController` over the same model and actions, built with `EditorWindowPlacement.fixed()`
/// and never shown: each push reaches it, so a test reads its subtitle, `available` and validation, and
/// its window's close reaches the coordinator through this editor. Its `present()` and its close sheet
/// are never called.
final class FakeEditor: EditorPresenting {
    struct Push: Equatable {
        var record: CaptureRecord?
        var saveFolder: URL?
        var isDeleting: Bool
    }

    let model: EditorModel
    let actions: EditorActions
    let title: String
    let representedURL: URL?
    /// The real controller, when the world builds editors with windows.
    let controller: EditorWindowController?
    var onClose: ((any EditorPresenting) -> Void)?

    private(set) var presentCount = 0
    private(set) var pushes: [Push] = []
    /// Every close sheet asked for, held or not.
    private(set) var askCount = 0
    var answers: [Bool] = []
    var holds = false
    private let sheet = SingleWaiter(cancelled: false,
                                     secondEntry: "FakeEditor was asked again while its close sheet was held")

    var isAsking: Bool { sheet.isWaiting }

    init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, withWindow: Bool) {
        self.model = model
        self.actions = actions
        self.title = title
        self.representedURL = representedURL
        controller = withWindow
            ? EditorWindowController(model: model, actions: actions, title: title, representedURL: representedURL,
                                     cascadeFrom: nil, placement: .fixed())
            : nil
        controller?.onClose = { [weak self] _ in
            guard let self else { return }
            self.onClose?(self)
        }
    }

    func present() {
        presentCount += 1
    }

    func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) {
        pushes.append(Push(record: record, saveFolder: saveFolder, isDeleting: isDeleting))
        controller?.recordDidChange(record, saveFolder: saveFolder, isDeleting: isDeleting)
    }

    /// As the real sheet: true at once with nothing to save. Otherwise the scripted answer: true is
    /// Don't Save (or a Save that wrote), false is Cancel (or a Save that failed). Nothing is saved here.
    func askToSaveBeforeClosing() async -> Bool {
        askCount += 1
        guard model.hasUnsavedChanges else { return true }
        guard holds else { return answers.isEmpty ? true : answers.removeFirst() }
        return await sheet.wait()
    }

    /// Answers the held sheet; later ones come from `answers`.
    func answer(_ proceed: Bool) {
        holds = false
        sheet.resume(proceed)
    }

    /// The window closing: the real window's close when there is one (its `windowWillClose` calls
    /// `onClose`), else `onClose` here. Never the close sheet.
    func close() {
        if let controller {
            controller.close()
        } else {
            onClose?(self)
        }
    }
}

/// `EditorActions` for a controller a test builds with no coordinator: every call in order, the image
/// each delivering call was handed, and scripted answers (Save and Save As write, Upload is enqueued
/// and written, unless the test says otherwise). No call waits.
final class FakeEditorActions {
    enum Call: Equatable {
        case save
        case saveAs(URL)
        case saveAsSuggestion
        case copy
        case upload(asNew: Bool)
        case objectCopy
        case objectPaste
        case exportFailed(message: String, title: String)
        case unusableBackgroundImage(String)
    }

    private(set) var calls: [Call] = []
    /// What Save, Save As, Copy and Upload were handed, in order.
    private(set) var images: [ScaledImage] = []
    var saves = true
    var uploadOutcome = EditorUploadOutcome(wroteLocally: true, enqueued: true)
    var suggestion = EditorNaming.SaveAsSuggestion(fileName: "Screenshot.png", directory: nil)
    var clip: Data?

    var actions: EditorActions {
        EditorActions(
            save: { image in
                self.calls.append(.save)
                self.images.append(image)
                return self.saves
            },
            saveAs: { image, url in
                self.calls.append(.saveAs(url))
                self.images.append(image)
                return self.saves
            },
            saveAsSuggestion: {
                self.calls.append(.saveAsSuggestion)
                return self.suggestion
            },
            copy: { image in
                self.calls.append(.copy)
                self.images.append(image)
            },
            objectClipboard: EditorObjectClipboard(
                copy: { data in
                    self.calls.append(.objectCopy)
                    self.clip = data
                },
                paste: {
                    self.calls.append(.objectPaste)
                    return self.clip
                },
                canPaste: { self.clip != nil }),
            upload: { image, asNew in
                self.calls.append(.upload(asNew: asNew))
                self.images.append(image)
                return self.uploadOutcome
            },
            exportFailed: { message, title in self.calls.append(.exportFailed(message: message, title: title)) },
            unusableBackgroundImage: { name in self.calls.append(.unusableBackgroundImage(name)) })
    }
}

extension EditorWindowPlacement {
    /// A fixed visible frame (a 1440 x 900 display under a 25 pt menu bar), no display, and a
    /// notification centre of its own that nothing posts to.
    static func fixed(_ visibleFrame: NSRect = NSRect(x: 0, y: 0, width: 1440, height: 875)) -> EditorWindowPlacement {
        EditorWindowPlacement(visibleFrame: { visibleFrame }, displayID: { _ in nil }, spaceChanges: NotificationCenter())
    }
}

/// Real editor controllers built in a test, never shown.
enum TestEditor {
    /// A `width` x `height` mid-grey capture at `scale`.
    static func image(width: Int = 64, height: Int = 32, scale: CGFloat = 2) throws -> ScaledImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ScaledImage(image: try #require(context.makeImage()), scale: scale)
    }

    /// A controller over `image` with `FakeTileRenderer`, the standard defaults, `actions` and
    /// `EditorWindowPlacement.fixed()`, told about `record` (a capture with no file, never uploaded,
    /// unless the test passes another) as the coordinator's first push does before the window would show:
    /// until then `available` is empty and every document action is refused. The test closes it
    /// (`controller.close()`), which asks nothing.
    static func make(_ actions: FakeEditorActions, image: ScaledImage? = nil, title: String = "Shot.png",
                     record: CaptureRecord? = CaptureRecord(fileURL: nil, pixelWidth: 64, pixelHeight: 32, appName: nil),
                     saveFolder: URL? = nil) throws -> EditorWindowController {
        let model = EditorModel(recordID: record?.id ?? UUID(), image: try image ?? Self.image(),
                                renderer: FakeTileRenderer(), defaults: .standard)
        let controller = EditorWindowController(model: model, actions: actions.actions, title: title,
                                                representedURL: nil, cascadeFrom: nil, placement: .fixed())
        controller.recordDidChange(record, saveFolder: saveFolder, isDeleting: false)
        return controller
    }
}
```

`TestEditor.make` pushes a record because `available` is empty until the first push (EWC:50-52) and `permits`
(EWC:180-182) then refuses every document action silently; the first scratch run of the Copy test timed out on
exactly that.

### 4.2 `CoordinatorWorld` (World:48, :116-117, :141-144)

```diff
@@ -46,6 +46,11 @@
     /// The lanes' plan; a test sets another before `makeCoordinator()`.
     var multipartPlan = MultipartPlan.standard
     private(set) var shutterCount = 0
+    /// Every editor the coordinator built, in order (editor seam). None is ever shown.
+    private(set) var editors: [FakeEditor] = []
+    /// When true, each editor also owns a real `EditorWindowController`, never shown, that the
+    /// coordinator's pushes reach (`FakeEditor.controller`). Set before the coordinator opens one.
+    var editorsHaveWindows = false
     /// The recorder's world, driver and chrome.
     let recording: RecordingTestWorld
     let driver: FakeRecordingDriver
@@ -115,6 +120,12 @@
             notifier: notifier,
             overlay: cards,
             clipboard: clipboard,
+            makeEditor: { [weak self] model, actions, title, representedURL in
+                let editor = FakeEditor(model: model, actions: actions, title: title, representedURL: representedURL,
+                                        withWindow: self?.editorsHaveWindows ?? false)
+                self?.editors.append(editor)
+                return editor
+            },
             makeDestination: { config, credentials in factory.make(config, credentials) },
             multipartPlan: multipartPlan,
             uploadSleep: { _ in },
@@ -138,7 +149,16 @@
         return coordinator
     }
 
+    /// The last editor built for `id`.
+    func editor(for id: UUID) -> FakeEditor? {
+        editors.last { $0.model.recordID == id }
+    }
+
     func removeAll() {
+        // A built window is closed (which asks nothing), so it does not outlive the test.
+        for editor in editors {
+            editor.controller?.close()
+        }
         try? FileManager.default.removeItem(at: root)
         defaults.removePersistentDomain(forName: suiteName)
     }
```

The flag is read when an editor is built, not when the coordinator is, so a test may set it after
`makeCoordinator()`. A second coordinator over the same world (the relaunch tests) appends to the same list, and
`editor(for:)` returns the newest.

### 4.3 `FakeClipboard` keeps the PNG (Fakes:167-173)

`FakeClipboard.Copy` records `.image` and `.pngAndTIFF` without the bytes (`FakeClipboard.Copy`, Fakes:167-173), so no test can say
what Preview's New from Clipboard would show. A fake change, not a seam:

```diff
     private(set) var copies: [Copy] = []
+    /// The PNG of every `.image` and `.pngAndTIFF` copy, in order (editor seam: what Preview's New from
+    /// Clipboard would read).
+    private(set) var pngs: [Data] = []
     var changeCount = 0
     var annotationClip: Data?
 
     func setString(_ string: String) { write(.string(string)) }
-    func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int { write(.image) }
-    func copy(pngData: Data, tiffData: Data?) -> Int { write(.pngAndTIFF) }
+    func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int {
+        pngs.append(pngData)
+        return write(.image)
+    }
+
+    func copy(pngData: Data, tiffData: Data?) -> Int {
+        pngs.append(pngData)
+        return write(.pngAndTIFF)
+    }
+
```

### 4.4 `EditorToolbarTests.makeEditor` (TidyShotTests/EditorToolbarTests.swift:65)

```swift
// Before
        return EditorWindowController(model: model, actions: actions, title: title, representedURL: nil, cascadeFrom: nil)
// After
        return EditorWindowController(model: model, actions: actions, title: title, representedURL: nil, cascadeFrom: nil,
                                      placement: .fixed())
```

So the one existing test that builds a controller stops reading the screens and registering with NSWorkspace.
`measuredToolbarFitsASmallDisplay` passes with the fixed frame (it measures the toolbar, not the screen).


## 8. The controller-alone tests (full Swift, as run)

New suite file `TidyShotTests/EditorWindowControllerTests.swift`. These are the lines tests-A moved from A because
they need a constructed controller (`docs/superpowers/notes/2026-10-30-checklist-sweep/tests-A.md`, Reclassified).

```swift
import AppKit
import Foundation
import Testing
@testable import TidyShot

/// The real editor window controller, built over `FakeEditorActions` with `EditorWindowPlacement.fixed()`
/// and never shown: no `present()`, no screen read, nothing registered with NSWorkspace. Each test closes
/// it, which asks nothing.
@Suite(.timeLimit(.minutes(1)))
struct EditorWindowControllerTests {
    func item(_ controller: EditorWindowController, _ identifier: NSToolbarItem.Identifier) throws -> NSToolbarItem {
        try #require(controller.window?.toolbar?.items.first { $0.itemIdentifier == identifier })
    }

    func tools(_ controller: EditorWindowController) throws -> NSSegmentedControl {
        try #require(try item(controller, .tools).view as? NSSegmentedControl)
    }

    func key(_ characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                      context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: false, keyCode: 0))
    }

    /// phase-4a :56, phase-4c :94, phase-7c :72. The toolbar's items in order; the fourteen tools; Copy, Save and
    /// Upload as plain buttons with no menus and their tool tips, Upload prominent; the Options tip; the Background
    /// button after Options with its symbol's description and tip.
    @Test func theToolbarShowsTheToolsThenColourOptionsBackgroundZoomCopySaveAndUpload() throws {
        let controller = try TestEditor.make(FakeEditorActions())
        defer { controller.close() }
        let items = try #require(controller.window?.toolbar?.items)
        #expect(items.map(\.itemIdentifier) == [.tools, .space, .color, .toolOptions, .background, .flexibleSpace,
                                                .zoom, .copyImage, .save, .upload])
        let tools = try tools(controller)
        #expect((0..<tools.segmentCount).map { tools.image(forSegment: $0)?.accessibilityDescription }
                == ["Select", "Redact", "Pixelate", "Blur", "Spotlight", "Rectangle", "Arrow", "Ellipse", "Line",
                    "Pencil", "Highlighter", "Text", "Counter", "Crop"])
        for (identifier, tip) in [(NSToolbarItem.Identifier.copyImage, "Copy the image (⌘C)"), (.save, "Save (⌘S)"),
                                  (.upload, "Upload and copy the link (⌘U)")] {
            let button = try item(controller, identifier)
            #expect(button.toolTip == tip)
            // A plain button: no view and no pull-down; AppKit's own menu form for the overflow has no submenu.
            #expect(button.view == nil)
            #expect(!(button is NSMenuToolbarItem))
            #expect(button.menuFormRepresentation?.submenu == nil)
        }
        #expect(try item(controller, .upload).style == .prominent)
        #expect(try item(controller, .toolOptions).toolTip == "Tool options")
        let background = try item(controller, .background)
        #expect(background.toolTip == "Background")
        #expect(background.image?.accessibilityDescription == "Background")
    }

    /// phase-4a :58, phase-4c :95. With the canvas taking the keys, V D X B R A pick Select, Redact, Pixelate, Blur,
    /// Rectangle and Arrow, S (either case) Spotlight and N Counter, and the toolbar's segment follows each.
    @Test func letterKeysPickToolsAndTheToolbarSegmentFollows() async throws {
        let controller = try TestEditor.make(FakeEditorActions())
        defer { controller.close() }
        let tools = try tools(controller)
        for (letter, tool) in [("v", EditorTool.select), ("d", .redact), ("x", .pixelate), ("b", .blur),
                               ("r", .rectangle), ("a", .arrow), ("s", .spotlight), ("n", .counter), ("S", .spotlight)] {
            if letter == "S" { controller.model.tool = .select }
            controller.canvasView.keyDown(with: try key(letter))
            #expect(controller.model.tool == tool)
            let index = try #require(EditorTool.toolbarOrder.firstIndex(of: tool))
            try await eventually { tools.selectedSegment == index }
        }
    }

    /// phase-4a :88. ⌘1 shows the natural point size and ⌘0 fits again; ⌘= and ⌘- zoom by 1.25 around the view's
    /// centre; the pop-up's Fit, 50 %, 100 %, 200 % and 400 % each set their zoom, and its title follows.
    @Test func zoomCommandsAndThePopUpsItemsSetTheZoom() async throws {
        let controller = try TestEditor.make(FakeEditorActions(), image: try TestEditor.image(width: 3000, height: 1600))
        defer { controller.close() }
        let model = controller.model
        let canvas = controller.canvasView
        let fit = model.transform.zoom
        #expect(model.transform.percent(captureScale: 2) < 100)

        controller.zoomToActualSize(nil)
        #expect(model.transform.percent(captureScale: 2) == 100)
        controller.zoomToFit(nil)
        #expect(model.transform.zoom == fit)
        let centre = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
        let fixed = model.transform.imagePoint(centre)
        controller.zoomIn(nil)
        #expect(abs(model.transform.zoom - fit * 1.25) < 1e-9)
        #expect(abs(model.transform.viewPoint(fixed).x - centre.x) < 0.5)
        controller.zoomOut(nil)
        #expect(abs(model.transform.zoom - fit) < 1e-9)

        let popUp = try #require(try item(controller, .zoom).view as? NSPopUpButton)
        let menu = try #require(popUp.menu)
        #expect(menu.items.dropFirst().map(\.title) == ["Fit", "50 %", "100 %", "200 %", "400 %"])
        for (index, percent) in [(2, 50), (3, 100), (4, 200), (5, 400)] {
            menu.performActionForItem(at: index)
            #expect(model.transform.percent(captureScale: 2) == percent)
            try await eventually { popUp.itemTitle(at: 0) == "\(percent) %" }
        }
        menu.performActionForItem(at: 1)
        #expect(model.transform.zoom == fit)
    }

    /// A push greys the toolbar's Save and Upload on a window that was never shown, and turns them on again;
    /// Copy stays on. (phase-4a :37, :145, :146, :147, :162 read this off their editors.)
    @Test func aPushGreysSaveAndUploadInTheToolbarAndCopyStaysOn() throws {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 64, pixelHeight: 32, appName: nil)
        let controller = try TestEditor.make(FakeEditorActions(), record: record)
        defer { controller.close() }
        let save = try item(controller, .save)
        let upload = try item(controller, .upload)
        let copy = try item(controller, .copyImage)
        #expect(save.isEnabled && upload.isEnabled && copy.isEnabled)

        controller.recordDidChange(record, saveFolder: nil, isDeleting: true)
        #expect(!save.isEnabled)
        #expect(!upload.isEnabled)
        #expect(copy.isEnabled)
        #expect(controller.window?.subtitle == EditorAvailability.deletingStatus)

        controller.recordDidChange(record, saveFolder: nil, isDeleting: false)
        #expect(save.isEnabled && upload.isEnabled)
        #expect(controller.window?.subtitle == EditorSaveTarget.noFileReason)
    }

    /// phase-4a :151. ⌘W (`performClose:`, D) on an editor with no changes closes it at once: the window agrees,
    /// no sheet comes up, and the close is reported.
    @Test func closingAnEditorWithNoChangesClosesItAtOnce() throws {
        let controller = try TestEditor.make(FakeEditorActions())
        defer { controller.close() }
        let window = try #require(controller.window)
        var closed: [any EditorPresenting] = []
        controller.onClose = { closed.append($0) }
        #expect(!window.isVisible)
        #expect(!controller.model.hasUnsavedChanges)
        #expect(controller.windowShouldClose(window))

        window.performClose(nil)

        #expect(window.attachedSheet == nil)
        #expect(closed.count == 1)
        #expect(closed.first === controller)
    }

    /// phase-7c :169. Copy (⇧⌘C, the toolbar's Copy) hands the coordinator the composed image: the background's
    /// canvas, with the annotations, as the export renders it.
    @Test func copyImageHandsTheActionsTheComposedImage() async throws {
        let actions = FakeEditorActions()
        let controller = try TestEditor.make(actions, image: try TestEditor.image(width: 16, height: 16))
        defer { controller.close() }
        let model = controller.model
        model.setBackground(BackgroundStyle(fill: .solid(RGBA(red: 1, green: 0, blue: 0)), padding: 4, cornerRadius: 0,
                                            shadow: false))
        model.commit(model.document.appending(.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 2, y: 2, width: 6, height: 4),
                                                                  color: RGBA(red: 0, green: 0, blue: 1, alpha: 1),
                                                                  lineWidth: 2))), actionName: "Add")
        let expected = try await model.renderExport()

        controller.copyImage(nil)
        try await eventually { actions.calls == [.copy] }

        let copied = try #require(actions.images.first)
        #expect(copied.image.width == 32)
        #expect(copied.image.height == 32)
        #expect(copied.scale == 2)
        #expect(try ImageEncoder.pngData(from: copied.image, scale: copied.scale)
                == ImageEncoder.pngData(from: expected.image, scale: expected.scale))
        #expect(model.hasUnsavedChanges)
    }
}
```

What the scratch runs taught: AppKit gives every plain `NSToolbarItem` a default `menuFormRepresentation` (the first
run failed `menuFormRepresentation == nil` on Copy, Save and Upload), so "no menus" is `!(item is NSMenuToolbarItem)`,
no view and no submenu; and `available` is empty until the first push (the first Copy run timed out).
