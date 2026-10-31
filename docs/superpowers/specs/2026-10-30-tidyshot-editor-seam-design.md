# TidyShot: Editor Seam (Phase CT-2) Design

Date: 2026-10-30. Branch `editor-seam` from `main` at a079a6f (CT-1 merged). Every file:line below is at a079a6f. Abbreviations: `+Editor` = `TidyShot/App/AppCoordinator+Editor.swift`, `Coord` = `TidyShot/App/AppCoordinator.swift`, `EWC` = `TidyShot/Editor/Window/EditorWindowController.swift`, `Env` = `TidyShot/App/AppEnvironment.swift`, `World` = `TidyShotTests/Support/CoordinatorWorld.swift`, `Fakes` = `TidyShotTests/Support/CoordinatorFakes.swift`.

## 1. Goal

The checklist sweep found 73 manual checklist lines that no test can drive while the coordinator builds the annotation editor's window itself (`docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md` section 1, lines 61-144; row 1 of its table, `EDITOR`, 73 lines, 65 needing it alone). `presentEditor` builds an `EditorWindowController` with `NSApp.orderedWindows` as its cascade source and presents it (+Editor:80-89); the controller's init sizes the window from `NSScreen.screens` and `NSEvent.mouseLocation` (EWC:123) and registers with `NSWorkspace.shared.notificationCenter` (EWC:103), both barred in the suite. So no test reaches an open editor, its four actions or the quit review: `CoordinatorEditorTests` says so in its header (CoordinatorEditorTests.swift:5-7).

This phase adds one seam, the editor presenter factory: a protocol for what the coordinator asks of an open editor and a factory closure on `AppEnvironment`, the pattern of `Notifying`, `QuickAccessCards`, `Clipboard` and `makeDestination` (harness design section 2). It writes 46 tests for the lines the seam reaches and marks 65 of the 73 lines: 25 in full and 40 in part. Eight lines need the real controller and wait for the next seam, `EDPLACE` (section 11). It goes first because it has the most lines of any seam (seams.md table, row 1), it is the smallest diff that reaches them (four files, 47 lines added and 15 removed by diffstat; 20 of the 45 non-blank added lines are doc comments), and the later editor seams (`EDPLACE`, `EDSAVEAS`, `CLOSESHEET`, `BEEP`) finish lines this seam starts (section 11).

The phase's notes are committed beside this design in `docs/superpowers/notes/2026-10-30-editor-seam/`. `lines-editor.md` gives each of the 73 lines with its text, its verdict and what stays. `tests-editor.md` is this design's catalogue: for each test, its suite file, entry point, record, fakes, sequence, assertions, effort and the lines it covers, with every value a body needs. The plan copies each test from there; nothing in it depends on the git-ignored `.superpowers/` working files.

## 2. The seam

### 2.1 The protocol (EWC.swift, additive)

Inserted after `EditorActions` (EWC:18-32) and before the class's doc comment (EWC:34). `Notifying` (Notifier.swift:163), `QuickAccessCards` (QuickAccessController.swift:381) and `Clipboard` (Pasteboard.swift:118) sit beside their live types in the same way:

```swift
/// What the coordinator asks of an open annotation editor (the editor seam): `EditorWindowController`
/// in the app, `FakeEditor` in the suite. Class-bound, so the registry keeps one object per record and
/// `editorDidClose` and the quit review compare by identity (`===`). Construction, and the close
/// callback, are `AppEnvironment.makeEditor`'s.
protocol EditorPresenting: AnyObject {
    /// The editor's document; the coordinator reads `recordID` and `hasUnsavedChanges`.
    var model: EditorModel { get }
    /// Brings the editor forward (activates the app).
    func present()
    /// The coordinator's push (`pushEditorState`): the record as it is now (nil once deleted or
    /// pruned), the save folder, and whether a delete is running.
    func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool)
    /// The unsaved-changes sheet, for the quit review. True when the editor may go.
    func askToSaveBeforeClosing() async -> Bool
}
```

At the end of the file, after EWC:521: `extension EditorWindowController: EditorPresenting {}`. EWC:34-521 do not change. `model` (EWC:37), `present()` (EWC:147), `recordDidChange` (EWC:165) and `askToSaveBeforeClosing()` (EWC:460) already have these exact signatures. These four, plus construction, `onClose` (+Editor:84) and identity (+Editor:471, Coord:472), are everything the coordinator touches on the controller. A grep of `TidyShot/` finds no other caller of `EditorWindowController`'s `recordDidChange` or `onClose`: `recordDidChange` is called only at +Editor:127 and the controller's `onClose` is set only at +Editor:84 (the other `.onClose` hits are the Trim window's, +Trim:99, and the card's, QuickAccessController.swift:234, QuickAccessView.swift:67, :75, :119).

### 2.2 The factory on `AppEnvironment`

A new member, between `playShutter` and `now` (Env:35-36):

```swift
    /// Builds an annotation editor over the coordinator's model and actions, titled `title`, with
    /// `representedURL` as its proxy icon, not yet shown. `onClose` runs when its window closes.
    var makeEditor: @MainActor (_ model: EditorModel, _ actions: EditorActions, _ title: String,
                                _ representedURL: URL?,
                                _ onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting
```

The live closure in `live()`, between `playShutter:` and `now:` (Env:69-70). `live()`'s doc comment (Env:43-46) adds "the editor window" to its list.

```swift
            makeEditor: { model, actions, title, representedURL, onClose in
                // The window as presentEditor built it: cascaded 22 pt from the frontmost editor,
                // read now, before this one exists. Its close reaches the coordinator's callback.
                let controller = EditorWindowController(model: model, actions: actions, title: title,
                                                        representedURL: representedURL,
                                                        cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow })
                controller.onClose = { closed in onClose(closed) }
                return controller
            },
```

The closure is `@MainActor`, not `@Sendable`. It builds an `NSWindowController`, reads `NSApp`, and is called only from `presentEditor` on the main actor, as `confirm` and `playShutter` are (Env:34-35). The `@Sendable` members (`makeDestination`, `freeBytes`, `now`, `log`) are the ones the upload lanes call off the main actor. `onClose` is an argument, not a protocol member. EWC:41 types it `((EditorWindowController) -> Void)?`, and a requirement would have to retype that line. The coordinator sets it once, at construction (+Editor:84), and never reads it. Default isolation is `MainActor` in both targets (project.yml:30, :102).

### 2.3 The registry and the coordinator's calls

```diff
--- TidyShot/App/AppCoordinator.swift (Coord:258-259)
-    /// Open annotation editors, one per record.
-    @ObservationIgnored var editors: [UUID: EditorWindowController] = [:]
+    /// Open annotation editors, one per record: the window in the app, a fake in the suite.
+    @ObservationIgnored var editors: [UUID: any EditorPresenting] = [:]
--- TidyShot/App/AppCoordinator+Editor.swift (+Editor:81-85, :89, :469-471)
-        let controller = EditorWindowController(model: model, actions: editorActions(for: record.id), title: title,
-                                                representedURL: fileURL,
-                                                cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow })
-        controller.onClose = { [weak self] closed in self?.editorDidClose(closed) }
-        editors[record.id] = controller
+        let editor = environment.makeEditor(model, editorActions(for: record.id), title, fileURL,
+                                            { [weak self] closed in self?.editorDidClose(closed) })
+        editors[record.id] = editor
         pushEditorState(for: record.id)
         observeSaveFolderForEditors()
         Task { await RedactionRenderer.shared.warmUp(with: image.image) }
-        controller.present()
+        editor.present()
-    private func editorDidClose(_ controller: EditorWindowController) {
-        let id = controller.model.recordID
-        guard editors[id] === controller else { return }
+    private func editorDidClose(_ editor: any EditorPresenting) {
+        let id = editor.model.recordID
+        guard editors[id] === editor else { return }
```

`presentEditor`'s doc comment (+Editor:72-73) says the editor is built "through `environment.makeEditor` (the window in the app, a fake in the suite)". `===` is declared on `AnyObject?`. A class-bound existential converts to it, so both identity checks compile and compare as before. `editors[record.id] == nil` (+Editor:40) is an `Optional` nil comparison and is unchanged. `editorActions(for:)` (+Editor:98-122), `presentEditor` and `editorDidClose` stay `private`. The fake gets the actions value through `makeEditor`, and Swift access control applies where a closure is defined, not where it is called.

### 2.4 `reviewEditorsBeforeQuit`, unchanged byte for byte (Coord:466-477)

```swift
    func reviewEditorsBeforeQuit() async -> Bool {
        for controller in Array(editors.values) where controller.model.hasUnsavedChanges {
            guard editors[controller.model.recordID] === controller else { continue }
            controller.present()
            guard await controller.askToSaveBeforeClosing() else { return false }
        }
        return true
    }
```

`controller` is now `any EditorPresenting`, and every member it uses resolves on the protocol. The loop variable keeps its name. `hasUnsavedEditors` (+Editor:7-9), `holdsQuit` (Coord:457-459), `quitNeedsHold` (Coord:462-464) and `AppDelegate.applicationShouldTerminate` (AppDelegate.swift:69-84) are unchanged.

### 2.5 What does not change

Today, `presentEditor` evaluates the init's arguments left to right (`model`, `editorActions(for:)`, `title`, `fileURL`, then `NSApp.orderedWindows.first`). Then come the init, `onClose`, the registry, the first push, the folder observation, the warm-up, `present()`, the card's close and `closedOverlays` (+Editor:80-93). After the change, the factory's arguments are evaluated first, then `NSApp.orderedWindows.first` and the same init inside the live closure, then `onClose`, and then the same sequence. The objects, the arguments and the order are the same, and the cascade source is still read before the new window exists. `AppEnvironment`'s memberwise init gains `makeEditor`. It has two callers: `live()` (Env:55) and `CoordinatorWorld.environment` (World:109).

What the user sees is unchanged. The editor opens at the same size, on the screen under the mouse, cascaded 22 pt from the frontmost editor (EWC:114-132), with the same title, proxy icon, toolbar, subtitle, greyed items and beeps. The registry entry still owns the window (`isReleasedWhenClosed = false`, EWC:84), and it is dropped through `windowWillClose` → `onClose` → `editorDidClose` (EWC:498-504). ⌘W's sheet runs as before (`windowShouldClose`, EWC:444-453; `askToSaveBeforeClosing`, EWC:460-492). Annotate on an open capture brings its window forward (+Editor:16-18). The card still closes `.editorOpened` and is not restorable (+Editor:90-93). The renderer still warms up on open and frees its caches when the last editor closes (+Editor:472-476). The quit review asks the same editors in the same order.

`EditorWindowController`'s body, `EditorToolbar`, `EditorModel`, `AppDelegate`, the Trim window (`+Trim:84-105`, `TRIM`) and every other `TidyShot/` file are untouched. The minimal design built this diff with the fake in section 3 under Swift 6, default `MainActor` isolation and `NonisolatedNonsendingByDefault`: `Test run with 2277 tests in 192 suites passed`, and its five seam tests caught two mutations. The judge re-ran that suite in its tree (5 tests, passed). The protocol sat in `AppEnvironment.swift` there; putting it in EWC.swift moves the file only. The facts review then built this section's diff as written, the fakes of section 3 and all 46 catalogue tests in a scratch tree (`Test run with 2319 tests in 195 suites passed`, with one extra test of its own; the Release build succeeded), and the review fixes were rebuilt there: `Test run with 2320 tests in 195 suites passed` with a second probe, and `** BUILD SUCCEEDED **` in Release (section 12).

## 3. The fakes

### 3.1 New: `TidyShotTests/Support/EditorFakes.swift`

```swift
import Foundation
import Testing
@testable import TidyShot

/// An open editor in the suite: the coordinator's model and actions, every call made on it, the close
/// sheet's answers; no window. The helpers commit a text being typed first, as every document action
/// and the sheet do (EditorWindowController.swift:188, :195, :208, :221, :228, :461), and apply results
/// as the controller does (`exportAndDeliver` :288-296, `performUpload` :268-283); `close()` stands
/// for `windowWillClose`.
final class FakeEditor: EditorPresenting {
    /// One push, and what the controller derives from it (recordDidChange, :165-176).
    struct Push: Equatable {
        var record: CaptureRecord?
        var saveFolder: URL?
        var isDeleting: Bool
        var available: Set<EditorAction> {
            EditorAvailability.actions(record: record, saveFolder: saveFolder, isDeleting: isDeleting)
        }
        var status: String? {
            EditorAvailability.status(record: record, saveFolder: saveFolder, isDeleting: isDeleting)
        }
        var saveCommand: EditorSaveCommand { EditorSaveCommand.forSave(record: record, saveFolder: saveFolder) }
    }
    enum Call: Equatable { case present, askToSave, recordDidChange(Push) }
    /// A close sheet's answer. `Sendable` because `SingleWaiter` carries it.
    nonisolated enum CloseAnswer: Equatable, Sendable {
        case save, dontSave, cancel
        case saveAs(URL)
    }
    let model: EditorModel
    let actions: EditorActions
    let title: String
    let representedURL: URL?
    private let onClose: @MainActor (any EditorPresenting) -> Void
    private(set) var calls: [Call] = []
    private(set) var isClosed = false
    /// The close sheet's answers, in order; Cancel when they run out.
    var closeAnswers: [CloseAnswer] = []
    /// While set, the sheet stays up until `answer(_:)`. Its task cancelled (the test's `defer`) or a
    /// second sheet while one is up: Cancel.
    var holdsCloseSheet = false
    private let sheet = SingleWaiter(cancelled: CloseAnswer.cancel,
                                     secondEntry: "FakeEditor's close sheet was asked for again while it was up")
    init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?,
         onClose: @escaping @MainActor (any EditorPresenting) -> Void) {
        self.model = model
        self.actions = actions
        self.title = title
        self.representedURL = representedURL
        self.onClose = onClose
    }
    var presentCount: Int { calls.filter { $0 == .present }.count }
    var pushes: [Push] {
        calls.compactMap { call -> Push? in
            guard case .recordDidChange(let push) = call else { return nil }
            return push
        }
    }
    var isAsking: Bool { sheet.isWaiting }

    // MARK: EditorPresenting
    func present() { calls.append(.present) }
    func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) {
        calls.append(.recordDidChange(Push(record: record, saveFolder: saveFolder, isDeleting: isDeleting)))
    }
    /// As the live sheet (:460-492): true with nothing to save, else the answer carried out.
    func askToSaveBeforeClosing() async -> Bool {
        calls.append(.askToSave)
        model.commitTextEditing()
        guard model.hasUnsavedChanges else { return true }
        let answer: CloseAnswer
        if holdsCloseSheet {
            answer = await sheet.wait()
        } else {
            answer = closeAnswers.isEmpty ? .cancel : closeAnswers.removeFirst()
        }
        switch answer {
        case .save:
            // The live first button writes over only when the last push allows Save and ⌘S writes over
            // (:467-468, performSave :247-254); otherwise it is Save As…, or Save opening the panel.
            guard let push = pushes.last, push.available.contains(.save), push.saveCommand == .writeOver else {
                Issue.record("FakeEditor's sheet was answered Save where the live first button opens the save panel")
                return false
            }
            return await save()
        case .saveAs(let url): return await saveAs(to: url)
        case .dontSave: return true
        case .cancel: return false
        }
    }
    func answer(_ answer: CloseAnswer) {
        holdsCloseSheet = false
        sheet.resume(answer)
    }

    // MARK: The user
    /// The window closed: the coordinator's `onClose`, as `windowWillClose(_:)` calls it.
    func close() {
        isClosed = true
        onClose(self)
    }
    /// A blue box over the whole capture, committed as a tool does on mouseUp.
    func draw() {
        let size = CGSize(width: model.base.width, height: model.base.height)
        let box = ShapeBox(id: UUID(), rect: CGRect(origin: .zero, size: size), color: RGBA(red: 0, green: 0, blue: 1),
                           lineWidth: max(size.width, size.height))
        model.commit(model.document.appending(.rectangle(box)), actionName: "Add")
    }
    /// The export and its document: a text being typed committed, then a pending crop and background
    /// draft applied (:301-317).
    func export() async -> (image: ScaledImage, document: AnnotationDocument)? {
        model.commitTextEditing()
        model.applyCrop()
        model.commitBackgroundDraft()
        let document = model.document
        guard let image = try? await model.renderExport() else { return nil }
        return (image, document)
    }
    /// ⌘S writing over; skips the window's validation, so a test reaches the coordinator's own check.
    @discardableResult
    func save() async -> Bool {
        guard let (image, exported) = await export() else { return false }
        guard await actions.save(image) else { return false }
        if model.document == exported { model.markSaved() }
        return true
    }
    @discardableResult
    func saveAs(to url: URL) async -> Bool {
        guard let (image, exported) = await export() else { return false }
        guard await actions.saveAs(image, url) else { return false }
        if model.document == exported { model.markSaved() }
        return true
    }
    /// Copy (⌘C, ⇧⌘C): never marks saved.
    func copy() async {
        guard let (image, _) = await export() else { return }
        await actions.copy(image)
    }
    /// ⌘U, or ⌥⌘U with `asNew`: saved and closed as the outcome says, given whether anything changed.
    @discardableResult
    func upload(asNew: Bool = false) async -> EditorUploadOutcome {
        guard let (image, exported) = await export() else { return .refused }
        let outcome = await actions.upload(image, asNew)
        let unchanged = model.document == exported
        if outcome.marksSaved, unchanged { model.markSaved() }
        if outcome.closesWindow(documentUnchanged: unchanged) { close() }
        return outcome
    }
}

/// `environment.makeEditor` in the suite: every editor built, in order, kept after it closes.
final class FakeEditors {
    private(set) var built: [FakeEditor] = []
    func make(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?,
              onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting {
        let editor = FakeEditor(model: model, actions: actions, title: title, representedURL: representedURL,
                                onClose: onClose)
        built.append(editor)
        return editor
    }
    /// The newest editor built for `id`.
    func editor(for id: UUID) -> FakeEditor? {
        built.last { $0.model.recordID == id }
    }
}
```

This is the fake as built in the minimal design's tree, less an unused `prepare` hook and with shorter doc comments, and with two changes from the review. Its `export()` and its sheet commit a text still being typed first (`model.commitTextEditing()`), as every document action and the live sheet do through `canvasView.commitTextEditing()` (EWC:188, :195, :208, :221, :228, :461; CanvasView.swift:693-708), so a test that leaves a text uncommitted exports it and ends clean, as the window would. And the issue a `.save` answer records names both cases in which the live first button opens the save panel: Save refused by the last push (the button is Save As…, EditorSaveTarget.swift:101-103) and Save with nothing to write over (`performSave`, EWC:247-254). The fake as written here was built and run (section 12). `FakeEditor`, `FakeEditors` and `SingleWaiter` are main-actor under the test target's default isolation. `CloseAnswer` is `nonisolated` and `Sendable` because `SingleWaiter<Value: Sendable>` requires it (Fakes:375). `Push` calls the three `nonisolated` statics that EWC:165-176 calls: `EditorAvailability.actions` (EditorSaveTarget.swift:121), `.status` (:149) and `EditorSaveCommand.forSave` (:78). `upload(asNew:)` applies `marksSaved` and `closesWindow(documentUnchanged:)` (EditorUploadPlan.swift:227, :233) as `performUpload` does (EWC:271-276).

### 3.2 `FakeClipboard` keeps the PNG (Fakes:167-173)

This changes a fake and adds no seam; no existing `copies ==` expectation changes:

```diff
     private(set) var copies: [Copy] = []
+    /// The PNG of every `.image` and `.pngAndTIFF` copy, in order (what Preview's New from Clipboard reads).
+    private(set) var pngs: [Data] = []
@@
-    func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int { write(.image) }
-    func copy(pngData: Data, tiffData: Data?) -> Int { write(.pngAndTIFF) }
+    func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int { pngs.append(pngData); return write(.image) }
+    func copy(pngData: Data, tiffData: Data?) -> Int { pngs.append(pngData); return write(.pngAndTIFF) }
```

### 3.3 `CoordinatorWorld` additions

```diff
@@ -41,1 +41,3 @@
     let confirm = FakeConfirm()
+    /// Every editor the coordinator opened (`environment.makeEditor`); no window is built.
+    let editors = FakeEditors()
@@ -108,1 +110,2 @@
         let confirm = confirm
+        let editors = editors
@@ -123,1 +126,5 @@
             playShutter: { [weak self] in self?.shutterCount += 1 },
+            makeEditor: { model, actions, title, representedURL, onClose in
+                editors.make(model: model, actions: actions, title: title, representedURL: representedURL,
+                             onClose: onClose)
+            },
```

The header comment (World:11-17) adds "the editors". `makeCoordinator()` and `removeAll()` need nothing, since no fake owns a window. A second coordinator over the same world (the relaunch tests) appends to the same `built` list, and `editor(for:)` returns the newest. New, and test support only (not a fake, not a seam): `TidyShotTests/Support/EditorPixels.swift`, a `nonisolated enum` with `image`, `png(width:height:scale:white:)`, `decoded`, `dpiWidth`, `rgba`, `pixel`, `changedPixels`, `isBlue` and a main-actor `worldRed()`, each as tests-editor.md section 2.1 specifies. `CoordinatorWorld.pngData` is scale 1 and red only (World:180-182), and its red is a Generic RGB `CGColor` filled into an sRGB context (World:171-174), which reads back as `[255, 38, 0, 255]`, not `[255, 0, 0, 255]`; a test compares the world's red with `worldRed()`.

### 3.4 Driving an editor in a test

1. **Open it.** Call `coordinator.openEditor(recordID:)` or `openEditorAfterMenuTracking(recordID:)`. A file or download loads in a task, so wait with `try await eventually { world.editors.editor(for: id) != nil }` and then `#require` it. The retained capture (`coordinator.latestCapture = (id:, image:)`, as CoordinatorDeleteTests.swift:347 sets it) registers synchronously, which is how "opens at once" is asserted.
2. **Edit the real model, then act.** Edit with `editor.draw()`, or with `model.commit`, a text, a crop through `cropDraft`/`applyCrop`, or a solid background. Then `await editor.save()`, `saveAs(to:)`, `copy()` or `upload(asNew:)`. These return on their own (`editorUpload` returns once enqueued, +Editor:377-378), so a direct await is allowed. A held lane is watched with `eventually` on `destination.state` and released. For a check the window's validation would block, call `editor.actions.*` directly and say so in the doc comment. That reaches the coordinator's own write-time checks (+Editor:158, :184, :315), which exist because the window's set can lag.
3. **Answer the close sheet.** Only `reviewEditorsBeforeQuit()` asks for it. Script `editor.closeAnswers`, or hold the sheet: set `holdsCloseSheet = true`, run the review in a `Task`, register `defer { review.cancel() }` at once, gate it by `TaskWatch` (Fakes:420-429), wait with `eventually { editor.isAsking }`, call `editor.answer(_:)`, wait with `eventually { watch.hasReturned }`, then `await review.value`. `FakeConfirm` is held the same way (CoordinatorDeleteTests.swift:210-224: the confirm held, a second delete gated by `TaskWatch`); that test has no `defer`, and the `defer` cancelling the held task is CT-2's addition to the pattern. The `defer` matters when the test fails before it answers: the suite's time limit cancels only the test's own task (Fakes:416-419), and cancelling the held task is what makes `SingleWaiter` answer Cancel or No (Fakes:393-400) so nothing stays parked.
4. **Close the window.** `editor.close()` stands for `windowWillClose`. `upload()` calls it when the outcome says so. Assert `editor.isClosed` and `coordinator.editors[id] == nil`.

## 4. The tests

46 new tests in four suite files: 31 in the two new files, 15 added to two existing ones. `tests-editor.md` has each in full. Five are the minimal design's tests 1 to 5, already built and green; one of those (test 2) takes a different edit (tests-editor.md 2.6), and test 5 gains the `TaskWatch` gate on its delete (section 5). The catalogue writes all five out, so the plan copies them from it. Effort: S 17, M 24, L 5; seven tests are parameterized.

| Suite file | New? | Tests | What they drive |
|---|---|---|---|
| `CoordinatorEditorSaveTests` | new | 17 | Save over the file: the save folder, `pending/`, a locked file, a stale link before and after Phase 3, a crop at scale 1 and 2, text with an ellipse and a crop, a solid background, the drag copy. Save As…: upload only, elsewhere at 144 dpi, onto its own file, with a crop, with a background. Copy: notification off, with a crop, with a background. The clipboard rule for Save and Save As… |
| `CoordinatorEditorUploadTests` | new | 14 | Upload over a link and the first upload; upload only through a new pending file; no destination; Upload as New without a link; a pre-Phase-3 capture; a changed destination; a flat reopen; failed replaces, a relaunch (a second coordinator) and a folder change; the drag copy |
| `CoordinatorEditorTests` | existing (2 tests) | 14 | Opening: a second Annotate, a download and offline, the overlay off in each mode, stored defaults, a pre-4c record, a composed capture. The card: what is left to restore, a restored card's Annotate, the drag copy's reads. What the editor hears: a held upload, a delete asked, cancelled and confirmed, an editor opened during a delete, a pruned record. The quit review |
| `CoordinatorOverlayTests` | existing | 1 | A card whose delete is under way is not restorable (phase-6a:158's delete sentences) |

Each test's doc comment names its checklist lines by catalogue key and current line, as the harness suites do. A test that covers a line in part says what stays and whose it is. `CoordinatorEditorTests`' header (lines 5-7) is reworded: presenting now goes through `environment.makeEditor` and `world.editors`.

## 5. Rules for the tests

- `TidyShot/` changes only as section 2 says. No `private` member opens. A test that would need more is reported, not forced, and its line goes to a later seam.
- No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, the screen, a camera, a microphone, a sound or the network. `RedactionRenderer.shared` is process-wide. The warm-up on every open and the cache clear on the last close reach it (+Editor:88, :474; RedactionRenderer.swift:79-88), and CT-2's tests are the first in the suite to do so (`RedactionRendererTests` and `RedactionExportTests` each make their own renderer, RedactionRendererTests.swift:74, RedactionExportTests.swift:37). No test observes it: the actor runs one call at a time, a cleared cache leaves its context usable (RedactionRendererTests.swift:90-95), and the tile cache asks it only for effects (Annotation.swift:101-105). So **no test commits an effect** (redact, blur, pixelate); tests draw boxes, strokes, text, counters and spotlights. The warm-up tasks can outlive their tests and touch nothing a test reads. Every coordinator call that takes an intent gets an explicit `CaptureIntent(action:)`. History is loaded with `history.load()`, never `start()`: `start()` removes the `tmp/` statics (Coord:294-300). The coordinator's `HistoryStore` prunes against the real `Date()` (HistoryStore.swift:23, Coord:278), so retention tests stamp records relative to `Date()`. Backgrounds are solid only. A desktop picture or a custom image would read the wallpaper or `CustomBackgroundStore.shared` (TidyShot/Background/BackgroundFillSource.swift:10-14). No test calls `restoreClosedOverlay()` until `canRestoreClosedOverlay` has been required false, since a restore reads `NSScreen.screens` (+Overlay:56, :87-90).
- Held fakes are cancellable and single-entry. No test awaits directly on a call whose only way out is the behaviour under test (`eventually`, UploadQueueTests.swift:42; `TaskWatch`), and that includes a delete whose confirm is held: the delete's task is gated by `TaskWatch` before `await delete.value`. A held PUT is released in a `defer`; a held sheet's or confirm's task is cancelled in a `defer` (3.4, step 3). A test that held a PUT also releases it and waits for `isUploading == false` before it returns, so `handle(.uploaded)` does not save history after `removeAll()`.
- **Nothing an edit starts outlives its test.** An edit that reaches `applyLocalEdit` starts the thumbnail task (+Editor:217, :249-275), which saves history when it lands (HistoryStore.swift:199-215) and would recreate the world's folders after `removeAll()` (ThumbnailStore.swift:44-45). So a test whose action reached `applyLocalEdit` ends with the suite helper `settledEdit(coordinator, id)`, which waits until the record names `thumbnails.fileName(for: id, editedAt: world.date)`; a test's second edit of one record first moves `world.date` on by a second, so its thumbnail gets a new name to wait for. A test that compares a whole record after a Save or an Upload waits for that name first, or the comparison races the task. A `finishSave` test waits for the capture's own thumbnail (+Save:288-309) the same way.
- **A relaunch** is a second `world.makeCoordinator()` and `history.load()` (never `start()`). Before it, the first coordinator is quiescent: no upload running, the edit's thumbnail named. After it, the test calls nothing on the first coordinator and does not run `world.clock`, since the first coordinator still holds its folder observation, its drag clean-ups and its own `HistoryStore` over the same `history.json` (+Editor:137-152, +DragOut:261-276, HistoryStore.swift:66-70).
- Each test owns its `CoordinatorWorld`, with `defer { world.removeAll() }`. Suites are `@Suite(.timeLimit(.minutes(1)))`, with no `.serialized`. Save-folder cases call `world.storeSaveFolder()` (World:150-156) before `makeCoordinator()`. A second folder is `world.saveLocation.store(_:)` on `<root>/Other/`. The minimal design's built tests wrote over a bookmarked file this way, which settles harness D25.
- **The fake editor.** Its helpers replay the controller's rules, and the controller's own lines do not run. A line that names the unsaved dot, the subtitle as shown, a greyed item, the window's key routing, the window's refusal of a shortcut or the window closing is therefore marked in part, with `EDPLACE` named for the rest. The window coming forward is `present()`'s own body (EWC:145-159), which the fake records and does not run; a line that names it is in part, and that part stays by hand for good, since ordering a window front is barred in the suite. **A constructed controller:** No test in this phase builds an `EditorWindowController`. Its init reads the screens (EWC:123) and registers with NSWorkspace (EWC:103). `EditorToolbarTests.makeEditor` (EditorToolbarTests.swift:54-66) already does both, and stays as it is until `EDPLACE` fixes it. No CT-2 test calls or copies `EditorToolbarTests.makeEditor`; it is a known exception owned by `EDPLACE`.
- Test names are camelCase sentences; parameterized tests use `@Test(arguments:)`. The suite stays green after every task. The Release build is run at the end.

## 6. The marks

When a test lands, its lines get marks as CT-1's did (CT-1 design section 5): `(suite: Suite.test)` for full, and `(suite, in part: Suite.test; by hand: <what>)` for part, appended to the end of the item's last line, wrapped at 120 columns with two-space continuation lines. A closing `______` stays last. The source is each test's "Covers" line in tests-editor.md and each line's "Stays" in lines-editor.md. A part mark's by-hand text names the other seam where there is one (`EDPLACE`, `EDSAVEAS`, `CLOSESHEET`, `BEEP`, `SAVEAS`, `PINS`, `SCREENS`, `QASTACK`, `TARGET`, `EDDEFAULTS`, `BGPOP`, `APPDELEGATE`). As in CT-1 (D13), a mark also names any existing test that pins a part of the line (`EditorSaveTargetTests`, `EditorUploadPlanTests`, `EditorClipboardTests` and others). 65 lines are marked, 25 in full and 40 in part. The 8 deferred lines stay unmarked. The checklists have moved since e011d2f, so the script finds each line by its text. Each entry names the catalogue key and an anchor that occurs once in its checklist at the branch head. The script asserts that each anchor matches one line, that every test a mark names exists (`func <name>(` in `TidyShotTests/`), that no item is marked twice, and that none of the 65 lines carries a mark already (none did at a079a6f, lines-editor.md header). Where a line's text is at odds with the code (section 10, call 9), the line's text is not changed and the mark says what the test pins. Three wording rules keep the marks reading one way. A stand-in is named, not called by hand: "Quick Look is the decode", "Preview is the `pngs` decode", "the link serving is the PUT body", "`sips` is the decode and the DPI read"; "by hand" is kept for the real bucket, the drawn UI and the real quit and relaunch. A mark citing a write-time refusal (phase-4a:127, :145, :146) says it pins the coordinator's check, and that the window's "do nothing" is its validation's (`EDPLACE`). And where a part line's test sets up a capture's own state that the line itself checks (phase-4a:119's "the image goes to the clipboard", phase-4a:120's copy with "Also copy image" on), the mark says the capture step is set up as +Save:57-67 leaves it and that no test drives it today (`TARGET`), and the line joins `TARGET`'s row (section 11). A full line whose test sets up such state (phase-4a:52, :115, :116, :117, :118) carries the plain `(suite: Suite.test)` mark; the same sentence lives in its Stays in lines-editor.md only, since the set-up state is the test's precondition, not a check the line makes. coordinator-split:43 is read that way too: its capture is the entry to the editor flow it checks, so its Stays names no `TARGET`.

## 7. Settings, entitlements, packages

None change. `project.yml` does not change: the test target takes `TidyShotTests/` whole, less `Fixtures/**`, which it adds as a resources folder (project.yml:92-97), so the four new files are picked up by `xcodegen generate`. There is no new setting, entitlement or package.

## 8. Tests summary

`Test run with 2272 tests in 191 suites passed` at a079a6f → `Test run with 2318 tests in 193 suites passed`. That is 46 new `@Test` functions, each counted once by `xcodebuild`, parameterized or not, and 2 new suite files. `EditorFakes.swift` and `EditorPixels.swift` hold no tests. The suite's noise lines are unchanged, and `MovieSamples` is untouched.

## 9. Hand checks (short)

The live closure (section 2.2) never runs in the suite: `live()` builds `AppSettings.shared`, the Keychain store and the notifier. So `docs/testing/editor-seam-manual-checklist.md`, written at close-out, checks that the real editor behaves as before:

1. Annotate from a card and from a Recent Captures row each open the editor at the same size as before. The title is the file name for a save-folder capture (with its proxy icon) and `Capture <time>` otherwise. A second Annotate on another capture opens a window cascaded 22 pt from the first. Annotate on a capture whose editor is open brings that window forward, and no second window opens.
2. Draw, then ⌘S: the save-folder file shows the edit and the unsaved dot clears. ⌘C posts `Image copied`. ⌘U closes the editor, the row uploads, and the link is copied.
3. ⌘W on a changed editor shows the close sheet. Cancel keeps the editor open; Don't Save closes it. Annotate on the same capture then opens a fresh editor. ⌘W on a clean editor closes it at once.
4. Quit with a changed editor: the sheet appears on it. Cancel keeps TidyShot running; quit again and Don't Save quits.

## 10. The design's calls (for Tim to overrule)

1. **One seam, `EDITOR`.** `EditorWindowPlacement`, which would put the controller's screen read and workspace observer behind closures, is a second seam: context.md says "No other seam". It is deferred as `EDPLACE`. Its diff, fakes and six controller tests were built and passed in the constructed design's tree (`2283 tests in 193 suites`, ten runs). Of the 13 lines tests-A moved because they read a constructed controller, 5 get part cover now and 8 none.
2. **The protocol is `EditorPresenting`**, with four members, class-bound. It lives in EWC.swift after `EditorActions`, and the conformance is an empty extension at the end of the file (2.1).
3. **The factory is one `@MainActor` closure, `makeEditor`.** It takes the model, the actions, the title, the represented URL and the close callback. `onClose` is a factory argument, not a protocol member, so EWC:41 is untouched (2.2).
4. **The registry becomes `[UUID: any EditorPresenting]`.** `reviewEditorsBeforeQuit` stays byte for byte, and its loop variable is not renamed (2.3, 2.4).
5. **No presenter type.** The rejected presenter design would have added about 100 production lines, rewritten `recordDidChange` and kept a second copy of `available` and `saveCommand`. The fake's `Push` reads the same three pure functions instead (3.1).
6. **Names and support.** `FakeEditor` and `FakeEditors` in `Support/EditorFakes.swift`, and `world.editors`, after `FakeNotifier` and `FakeCards`; the registry stays `coordinator.editors`. `FakeClipboard.pngs` (3.2) and `EditorPixels` (3.3) are support, not seams.
7. **The window's glue is marked in part.** The fake's helpers apply the controller's rules, but the controller's lines do not run. So a line naming the dot, the subtitle as shown, greying, key routing or closing at once is in part until `EDPLACE`. 17 of the 40 part lines have only that glue and checks by hand left, and two more (phase-4a:119, :120) have that glue and a capture-time copy no test drives (`TARGET`) (tests-editor.md section 9). One more, phase-4a:39, has only the window coming forward left, which is `present()`'s body and stays by hand (section 5).
8. **Suites.** `CoordinatorEditorTests` takes the opening, push and quit tests. The new `CoordinatorEditorSaveTests` and `CoordinatorEditorUploadTests` take the actions, named by behaviour as `CoordinatorSaveTests` and `CoordinatorUploadTests` are. One test goes to `CoordinatorOverlayTests` for phase-6a:158's delete sentences, so that line is marked in full.
9. **Lines at odds with the code; the tests pin the code and the wording is Tim's call** (tests-editor.md section 8). phase-4a:132's last step: Retry Failed Uploads does nothing for a failed replace, because the record returns to `.uploaded` (+Upload:708-719) and Retry takes only failed records (+Upload:496-507); the next ⌘U recovers it, and the test pins both. "After the retries" in phase-4a:131 and phase-4b:112: a 403 is not retried (TidyShot/Upload/Destination.swift:177-181). The failure notice's title is `Not uploaded` (+Upload:719, harness D14). phase-6a:199's "from the card": after an Annotate the card is closed and not restorable, and in upload-only mode ⌘S is Save As…. phase-7c:171 reopens flat only after the first editor has closed.
10. **The `EDPLACE` design is committed with this design.** The constructed angle's sections 2.1, 4 and 8 (its `EditorWindowController.swift` diff, its fakes and its controller-alone tests, all built and run in its scratch tree) are in the notes folder as `edplace-design.md`, with their section numbers kept, so tests-editor.md's references (by section and test name) resolve and the next phase starts from a built diff. seams.md gains an `EDPLACE` row, and the part lines join the rows of the seams their marks name (section 11).
11. **Five of the 13 constructed lines are marked in part now** (phase-4a:37, :145, :146, :162, phase-7c:169), through the pushes and the coordinator's copy, rather than left whole for `EDPLACE`; their marks name `EDPLACE` for the rest.
12. **`BEEP` widens.** seams.md's `BEEP` (row 32) replaces only the export failure's beep (EWC:314). The lines here also beep in `performUpload` (EWC:280) and in `EditorWindow.send` when the window's validation refuses a shortcut (EditorWindow.swift:45). One `beep` closure on the controller, handed to its window, carries every beep of the two (EWC:236, :280, :314, :464; EditorWindow.swift:45), rather than a new key per site. CanvasView's two beeps (CanvasView.swift:364, :439) are named by none of these lines and stay. The refusal itself is the validation (EWC:426-427), so it is `EDPLACE`'s; only the sound is `BEEP`'s.
13. **Two full lines become part.** phase-4a:39 (the window coming forward is `present()`'s body, section 5) and phase-6a:164 (no restore runs: a restore reads `NSScreen.screens`, +Overlay:94, :55-61, `SCREENS`). phase-6a:164's test gains a case for the restore's quiet download landing first (+Overlay:101 → +DragOut:69-89), after which Annotate reads the drag copy and posts no `Downloading` notice. Full 25, part 40.

## 11. Deferred, and what seams.md records

Lines this seam does not finish, by the seam that does (a line can be under more than one; seams.md table rows at a079a6f in brackets). Trim (`+Trim:84-105`) has the editor's shape and stays as it is (`TRIM`, row 9).

- **`EDPLACE`** (new key: the controller's visible frame, display and Space-change observer behind `EditorWindowPlacement`; built, call 10): 7 lines whole (phase-4a:56, :58, :88, :151; phase-4c:94, :95; phase-7c:72), phase-4a:107 with `BEEP`, and the window's glue in 30 part lines: the dot, the subtitle as shown, greying, key routing, the validation that refuses a shortcut, the window closing, and the background popover drawn in the window. 17 of the 30 have nothing else left, and phase-4a:119 and :120 have only the capture-time copy besides (`TARGET`) (tests-editor.md section 9).
- **`BEEP`** (row 32, widened by call 12): the sound of phase-4a:107 (`performUpload`, EWC:277-281) with `EDPLACE`, and of the shortcut refusals in 3 part lines (phase-4a:127, :145, :146; EditorWindow.swift:45), whose refusal itself is `EDPLACE`'s.
- **`EDSAVEAS`** (row 23): the editor's save panel or Replace prompt in 8 part lines (phase-4a:97, :102, :106, :145, :147, :148, :162; phase-7c:172). **`CLOSESHEET`** (row 26): the sheet in 2 (phase-4a:148, :155). **`APPDELEGATE`** (row 31): the real quit's reply in 1 (phase-4a:155; AppDelegate.swift:69-84).
- **`SAVEAS`** (row 6): 3 part lines (coordinator-split:44; phase-6a:198, :199). **`SCREENS`** (row 10): 2 (coordinator-split:44; phase-6a:164, the restore itself). **`PINS`** (row 11): 2 (coordinator-split:44, phase-6b:118). **`TARGET`** (row 3): 4 (phase-4a:119, :120, whose capture-time clipboard copy the tests set up and no test drives, section 6; phase-6b:118; phase-7c:187). **`BGPOP`** (row 21): 2 (phase-7c:171's switch turned on, whose setter reads `AppSettings.shared.backgroundStyle`, BackgroundPopoverView.swift:36-38; phase-7c:187's switch as the popover's binding shows it). **`QASTACK`** (row 15): 1 (phase-6a:131). **`EDDEFAULTS`** (row 29): 1 (phase-4c:201).
- **No seam:** phase-4a:39's window coming forward (`present()`'s body, EWC:147-152; ordering a window front is barred in the suite); whether phase-7c:171's second background is expected (Tim's call); the real bucket and the real relaunch the part marks name.

**seams.md at close-out.** seams.md keeps its rules: Lines counts every line that needs the seam, Alone the lines that need it and nothing else, Completes credits each line to the last of its seams in table order, and the table is sorted by Lines (seams.md:9-12). The close-out script edits it from this section and the catalogue:

1. Every one of the 73 lines stays under `EDITOR`, its entry gaining its CT-2 verdict (`CT-2: full`, `CT-2: in part`, `CT-2: deferred`).
2. A new row and section, `EDPLACE` (Editor window placement), lists its 38 lines: the 8 deferred and the 30 part lines above.
3. Each part line joins the row of every other seam its mark names, noted "also `EDITOR`, in part since CT-2": `EDSAVEAS` gains phase-4a:97, :102, :106, :145, :147, :148, :162; `CLOSESHEET` phase-4a:148; `BEEP` phase-4a:107, :127, :145, :146 (its Replaces line widens, call 12); `SAVEAS` phase-6a:199; `SCREENS` phase-6a:164; `BGPOP` phase-7c:171, :187; `TARGET` phase-4a:119, :120; `APPDELEGATE` phase-4a:155. These replace the free-text notes on phase-4a:97 and :148 under `EDITOR` (seams.md:83, :107). That is 57 new seam slots.
4. The counts, redone by those rules (worked from seams.md's own line lists, which reproduce its 347 / 225 / 279): 42 seams; 279 B lines, unchanged; Lines 404; Alone 186; Completes 279; 93 lines need two or more seams (54 before) and 16 seams unlock three or fewer (18 before); the first three seams complete 58 lines and the first ten 152. Rows that change, as Lines / Alone / Completes: `EDITOR` 73 / 26 / 26 (the 25 full lines and phase-4a:39); `EDPLACE` 38 / 0 / 24 (second in the table; it completes the 7 whole lines and the 17 glue-only ones); `TARGET` 34 / 26 / 28 (fourth; phase-4a:119 and :120 complete under it, after `EDPLACE`; phase-7c:187 now completes under `BGPOP`); `SAVEAS` 14 / 9 / 11; `SCREENS` 12 / 6 / 8; `EDSAVEAS` 11 / 2 / 8 (23rd to 12th); `BGPOP` 7 / 5 / 7; `BEEP` 5 / 1 / 5; `CLOSESHEET` 4 / 1 / 3; `APPDELEGATE` 2 / 1 / 2. The multi-seam and three-or-fewer sections are regenerated, and the script asserts the three sums.


## 12. Built notes

From the design's review; the close-out adds the suite line and Release build on the branch, the marks made and the seams.md edit. The design's review rebuilt the fakes and tests with its fixes in the facts review's scratch tree (a copy of the repository at a079a6f with section 2's diff applied): the three seam suites `Test run with 11 tests in 3 suites passed`, the rest of the catalogue `13 tests in 1 suite` and `26 tests in 1 suite` passed, the full suite `Test run with 2320 tests in 195 suites passed` (2272 + 46 catalogue tests + 2 probes), and the Release build `** BUILD SUCCEEDED **`. A probe with the fake's two text commits removed failed with 5 issues.

Built on `editor-seam` from the plan `docs/superpowers/plans/2026-10-30-editor-seam.md`: the full suite
`Test run with 2318 tests in 193 suites passed` (the baseline's 2272 tests in 191 suites, and 46 tests in two new suite
files and two existing ones) and the Release build `** BUILD SUCCEEDED **` with no `error:` or `warning:` line from the
compiler or the linker. 65 lines carry marks, 25 in full and 40 in part, and the 8 deferred lines none. seams.md has
section 11's edit, with one difference: sorted by Lines, `TARGET` (34) is third, ahead of `CAPSRC` (33), so the first
three seams complete 78 lines, not 58; every row's numbers, the three sums and the first ten's 152 are as section 11
gives. The hand checks of section 9 are `docs/testing/editor-seam-manual-checklist.md`, for Tim.

Built differently from this design and the catalogue. The plan's decisions D3 to D75 hold what the task writers changed
(the helpers' homes, the bodies kept as the review built them, the doc comments, the waits); these come from the
execution itself:
- The two first tests are stronger than the catalogue's entries (plan D76; fix commits 62b01c4 and fe0a799).
  `annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond` opens an upload-only capture (`addUploadOnly`)
  where the catalogue's entry (section 5, Opening) names a `pending/` file, and asserts that the object was downloaded
  once (`dataDownloadKeys == [key]`), so a dropped `openingEditorIDs` guard fails it.
  `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo` records the call count before the review and asserts exactly
  `[.present, .askToSave]` after it, so a review that stops calling `present()` fails, and after Don't Save asserts that
  both editors are still registered. The catalogue's entries keep their text; the marks of phase-4a:39 and phase-4a:155
  are unchanged.
- Six fix commits make a regression fail one test where it would have trapped the test process:
  `world.clipboard.pngs[0]` and `[1]` became `try #require(pngs.first)` or `pngs.last`, and the composed or uploaded
  size checks before an `EditorPixels.pixel` read became `try #require`. Task 2: f0b8bcb (the locked-file Save test) and
  fc58d18 (the background Save test, its saved file, thumbnail and reopened base). Task 3: 25dd4c1 (the Save As and Copy
  tests). Task 4: feb939c (the no-destination test) and 2edbeb3 (the upload over a link PUT body and the reopened
  uploaded capture's base). Task 7: ce7e971 (the held-upload test). No assertion was added or weakened, and no `pngs[`
  index is left in `TidyShotTests`. One read stays unguarded:
  `annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL` reads the saved file's pixel (3, 1) with
  no size check, as built.
- `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` fails in about 1 of 6 full runs, on the
  untouched baseline (bc6b5e5) as well. It does not use the coordinator's world or the editor, and it is not this
  phase's; a full run that fails only on it passes on a second run.
