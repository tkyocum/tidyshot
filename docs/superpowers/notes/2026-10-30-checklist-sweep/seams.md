# Seams for the B lines

Source: `catalogue.json` (1405 lines, 265 in category B), `reader-summaries.md`, and the 14 lines tests-A.md moved from A to B, so 279 B lines in all. Every seam below was checked against the code on `checklist-tests` at e011d2f (file:line as found there; where a reader's line number had drifted, the one here is the current one). A second pass re-checked every line list against the catalogue (all 265 B lines present, none listed twice under one seam, every "also" note matching the other seams the line is listed under, every header and table count matching its list) and corrected or completed 14 file:line citations that had drifted or were partial. The reconciliation of the four documents (critic.md) then added tests-A's 14 lines: 13 under `EDITOR` (each builds an `EditorWindowController`) and recording-r2:241 under `TMPDIRS`. That moved `TMPDIRS` from tenth to eighth in the table, ahead of `TRIM` and `SCREENS`; no line's Completes credit changed. CT-2 (`docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`, section 11) then built `EDITOR`: each of its 73 lines carries its CT-2 verdict, the new seam `EDPLACE` holds the 8 lines CT-2 deferred and the 30 it marked in part with the window's glue left, and the part lines also sit under the other seams their marks name (57 new seam slots). The table, the counts and the last sections were redone by the rules in the summary. CT-3 (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`, section 11) then built `CLOP`, `SAVEAS` and `LOG`: each of their 49 lines carries its CT-3 verdict (28 full, 18 in part, 3 deferred), and the part and deferred lines also sit under the other seams their marks name (6 new seam slots). The table, the counts and the last sections were redone again by the same rules, with seams of equal Lines kept in their old table order.

## Summary

- 279 B lines (265 from the catalogue, 14 from tests-A), 42 distinct seams.
- 182 lines need one seam; 97 need two or more (listed in their own section).
- 15 seams unlock three or fewer lines each.
- "Lines" counts every B line that needs the seam; "alone" counts the lines that need it and nothing else; "completes" counts the lines this seam finishes when the seams are added in table order (each line is credited to the last of its seams in that order, so every B line has exactly one home).
- The counts add up: Lines sums to 410 (182 one-seam lines, plus 228 seam slots held by the 97 lines that need two or more); Alone sums to 182; Completes sums to 279, every B line once. Read down the Completes column for a running total: the first three seams cover 78 lines, the first ten 150.
- Two dependencies hold throughout and are not repeated per line: `CAPSRC`, `SELINT` and `SCROLLCTL` are built on `TARGET` (they hand back displays and windows), and `POSTER` is reached only through `TRIM`.
- Two A lines name a seam in their evidence and need none; one A line has a second half that needs `TMPDIRS`; one B line has a part that is A (see the end).

| # | Seam | Key | Lines | Alone | Completes | Effort |
|---|---|---|---|---|---|---|
| 1 | Editor presenter factory | `EDITOR` | 73 | 26 | 26 | M |
| 2 | Editor window placement | `EDPLACE` | 38 | 0 | 24 | S |
| 3 | Value capture target | `TARGET` | 34 | 26 | 28 | M |
| 4 | Capture source (engine and selector) | `CAPSRC` | 34 | 8 | 8 | L |
| 5 | Clop optimiser and running check | `CLOP` | 23 | 22 | 22 | S |
| 6 | Card Save As panel | `SAVEAS` | 14 | 7 | 8 | S |
| 7 | Recording chrome factory | `RECCHROME` | 14 | 0 | 8 | S |
| 8 | Screen list for the card stack and pins | `SCREENS` | 14 | 6 | 10 | M |
| 9 | tmp/ directory statics | `TMPDIRS` | 13 | 7 | 8 | M |
| 10 | RecordingLog sink | `LOG` | 12 | 7 | 8 | S |
| 11 | Trim window factory | `TRIM` | 11 | 9 | 9 | L |
| 12 | Editor Save As sheet | `EDSAVEAS` | 11 | 2 | 8 | S |
| 13 | Headless pins | `PINS` | 10 | 5 | 9 | M |
| 14 | RecordingExtras window and camera factories | `EXTRAS` | 9 | 4 | 8 | M |
| 15 | Self-timer stage factory | `STAGE` | 9 | 1 | 6 | S |
| 16 | Status menu model | `STATUSMENU` | 8 | 5 | 8 | M |
| 17 | Background popover state | `BGPOP` | 7 | 5 | 7 | M |
| 18 | Quick Access stack internals | `QASTACK` | 6 | 5 | 6 | L |
| 19 | Upload settings form model | `UPLOADFORM` | 6 | 5 | 6 | M |
| 20 | Desktop covers behind a protocol | `COVERS` | 6 | 3 | 6 | S |
| 21 | Launch steps out of start() | `LAUNCH` | 6 | 3 | 6 | S |
| 22 | Scrolling capture behind a protocol | `SCROLL` | 6 | 2 | 6 | S |
| 23 | Workspace open and reveal | `WORKSPACE` | 6 | 2 | 5 | S |
| 24 | Editor export beep | `BEEP` | 5 | 1 | 5 | S |
| 25 | Selection overlay internals | `SELINT` | 4 | 3 | 4 | L |
| 26 | Editor close sheet | `CLOSESHEET` | 4 | 1 | 3 | S |
| 27 | URL command log closure | `URLLOG` | 4 | 2 | 4 | S |
| 28 | Recording chrome's not-filmed mapping | `CHROMEMAP` | 3 | 3 | 3 | S |
| 29 | Save folder chooser | `FOLDER` | 3 | 1 | 3 | S |
| 30 | Capture Text's copy step reachable | `COPYTEXT` | 2 | 2 | 2 | S |
| 31 | Quit reply decision | `APPDELEGATE` | 2 | 1 | 2 | S |
| 32 | Editor defaults store | `EDDEFAULTS` | 2 | 1 | 2 | S |
| 33 | Trim poster reader | `POSTER` | 2 | 0 | 2 | S |
| 34 | Preferred camera as a pure rule | `CAMPREF` | 1 | 1 | 1 | S |
| 35 | Camera session device behind a protocol | `CAMSESSION` | 1 | 1 | 1 | M |
| 36 | Desktop cover internals | `COVERSINT` | 1 | 1 | 1 | M |
| 37 | Template migration log | `MIGLOG` | 1 | 1 | 1 | S |
| 38 | Canvas modifier flags | `MODIFIERS` | 1 | 1 | 1 | S |
| 39 | Pasteboard target | `PASTEBOARD` | 1 | 1 | 1 | S |
| 40 | Scrolling session controller internals | `SCROLLCTL` | 1 | 1 | 1 | L |
| 41 | Background fill store | `BGFILL` | 1 | 0 | 1 | S |
| 42 | Mute ladder steps | `MUTESTEPS` | 1 | 0 | 1 | S |

## The seams, by lines unlocked

### 1. Editor presenter factory (`EDITOR`): 73 lines, 26 alone

- Replaces: `EditorWindowController(model:actions:title:representedURL:cascadeFrom: NSApp.orderedWindows...)` and `controller.present()` in the private `presentEditor` (TidyShot/App/AppCoordinator+Editor.swift:74; the controller is built and presented at :81-89); the `editors: [UUID: EditorWindowController]` map (AppCoordinator.swift:259); `reviewEditorsBeforeQuit` calling `present()` and `askToSaveBeforeClosing()` (AppCoordinator.swift:470-476). The private `editorActions(for:)` (+Editor.swift:98) and so `editorSave`, `editorSaveAs`, `editorUpload`, `editorCopy` (:157, :283, :312, :451) are reached only through the window.
- Shape: A closure on `AppEnvironment` (`makeEditor(model, actions, title, representedURL) -> any EditorPresenting`) returning a protocol with `present()`, `recordDidChange(_:saveFolder:isDeleting:)`, `model`, `onClose`, `askToSaveBeforeClosing()`. The fake keeps the `EditorActions` it was handed.
- Live: `EditorWindowController` conforms unchanged; the live closure builds it with `cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow }` as today.
- Effort for the seam: M
- Note: Save-folder cases also need `saveLocation.store(tempURL)` in the world, which the harness has not tried (D25).
- CT-2: Built on `editor-seam` (`docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`). Each line below carries its CT-2 verdict; a line marked in part also sits under every other seam its mark names, noted there as "also `EDITOR`, in part since CT-2".

Lines (73):

- `coordinator-split:43` Annotate the newest card, Save, then Upload [+Editor]. After… (also `EDPLACE`); CT-2: in part
- `coordinator-split:44` Pin, then the pin menu's three items [+Pins, +RecordActions]… (also `PINS`, `SCREENS`, `SAVEAS`); CT-2: in part
- `phase-4a:37` "Upload and copy URL", a large capture with Network Link… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); CT-2: in part
- `phase-4a:39` Annotate a capture whose editor is already open (from its…; CT-2: in part
- `phase-4a:49` Upload-only capture that finished uploading: after a moment (it…; the Wi-Fi-off half also needs FakeDestination.download(key:) to throw; CT-2: full
- `phase-4a:52` Settings > Overlay, turn "Show Quick Access overlay after…; CT-2: full
- `phase-4a:56` The toolbar shows, in order: the tools (Select, Redact… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); obsolete-E's corrected toolbar text goes with this line; CT-2: deferred
- `phase-4a:58` With the canvas focused, `V` `D` `X` `B` `R` `A` pick Select… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); CT-2: deferred
- `phase-4a:88` ⌘1 shows the picture at its natural point size and ⌘0 fits it… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); CT-2: deferred
- `phase-4a:94` Saved capture: Redact, ⌘S. The same file in the save folder now… (also `EDPLACE`); CT-2: in part
- `phase-4a:95` Capture uploaded with "Upload and copy URL": ⌘S rewrites the… (also `EDPLACE`); CT-2: in part
- `phase-4a:96` Capture from before Phase 3: ⌘S rewrites its file, with the… (also `EDPLACE`); CT-2: in part
- `phase-4a:97` Upload-only capture that finished uploading: Save is on… (also `EDPLACE`, `EDSAVEAS`); CT-2: in part
- `phase-4a:98` Upload-only capture whose upload failed: Redact, ⌘S rewrites…; CT-2: full
- `phase-4a:99` Lock the saved file (Finder, Get Info, Locked), edit, ⌘S: a Not… (also `EDPLACE`); CT-2: in part
- `phase-4a:102` Saved capture: edit, then ⇧⌘S. The save panel suggests the… (also `EDPLACE`, `EDSAVEAS`); CT-2: in part
- `phase-4a:106` ⇧⌘S on a saved capture and save over its own file (confirm… (also `EDPLACE`, `EDSAVEAS`); CT-2: in part
- `phase-4a:107` Edit, ⌘U, and keep drawing before the window closes (slow… (also `EDPLACE`, `BEEP`); moved from A by tests-A (a constructed EditorWindowController); CT-2: deferred
- `phase-4a:112` With "Show notification" off, Copy posts nothing. Turn it back…; CT-2: full
- `phase-4a:115` "Save and copy image" with "Copy image to clipboard" on…; CT-2: full
- `phase-4a:116` The same with ⇧⌘S in place of ⌘S, saving to the Desktop: the…; CT-2: full
- `phase-4a:117` Capture, copy some text in TextEdit, then Annotate, Redact…; CT-2: full
- `phase-4a:118` Capture, copy some text in TextEdit, then Annotate, Redact, ⌘S…; CT-2: full
- `phase-4a:119` "Upload and copy URL" with no destination (Forget Credentials… (also `EDPLACE`, `TARGET`); CT-2: in part
- `phase-4a:120` "Upload and copy URL" with "Also copy image" on: capture… (also `EDPLACE`, `TARGET`); CT-2: in part
- `phase-4a:123` Capture uploaded with "Upload and copy URL": Redact, then the… (also `EDPLACE`); CT-2: in part
- `phase-4a:124` Upload-only capture that finished uploading: Redact, ⌘U. The… (also `EDPLACE`); CT-2: in part
- `phase-4a:127` Saved capture never uploaded: ⌥⌘U beeps. ⌘U uploads it for the… (also `EDPLACE`, `BEEP`); CT-2: in part
- `phase-4a:129` Capture from before Phase 3: ⌘U shows the notice The earlier…; CT-2: full
- `phase-4a:130` Optional, with a second bucket: point Settings > Upload at it…; CT-2: full
- `phase-4a:131` Enter a wrong secret access key in Settings > Upload and press… (also `EDPLACE`); CT-2: in part
- `phase-4a:132` Folder change with a bad key: Settings > General, Choose…… (also `EDPLACE`); CT-2: in part
- `phase-4a:133` The same wrong key, ⌘U on an upload-only capture that finished… (also `EDPLACE`); CT-2: in part
- `phase-4a:145` Slow profile, "Upload and copy URL": capture something large… (also `EDPLACE`, `EDSAVEAS`, `BEEP`); moved from A by tests-A (a constructed EditorWindowController); CT-2: in part
- `phase-4a:146` With an editor open, press Delete on its row and leave the… (also `EDPLACE`, `BEEP`); moved from A by tests-A (a constructed EditorWindowController); CT-2: in part
- `phase-4a:147` Delete again and confirm: the subtitle reads This capture was… (also `EDPLACE`, `EDSAVEAS`); EDSAVEAS is an alternative to EDITOR for the Save As write; CT-2: in part
- `phase-4a:148` Editor open on a capture in the save folder: Settings >… (also `EDPLACE`, `EDSAVEAS`, `CLOSESHEET`); CT-2: in part
- `phase-4a:151` ⌘W on an editor with no changes closes it at once.… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); CT-2: deferred
- `phase-4a:155` Quit TidyShot from the menu with a changed editor: the sheet… (also `CLOSESHEET`, `APPDELEGATE`); CT-2: in part
- `phase-4a:162` Quit, set one record's `timestamp` in `history.json` to two… (also `EDPLACE`, `EDSAVEAS`); moved from A by tests-A (a constructed EditorWindowController); CT-2: in part
- `phase-4b:71` Saved pixel size: on a saved capture, crop to a readout of…; CT-2: full
- `phase-4b:73` Reopen the cropped capture with Annotate: the editor opens the…; CT-2: full
- `phase-4b:74` Uploaded pixel size: on a capture uploaded with "Upload and…; CT-2: full
- `phase-4b:75` Upload-only capture that finished uploading: crop, ⌘U. The link…; CT-2: full
- `phase-4b:76` Save As… (⇧⌘S) with a crop: the new PNG has the cropped pixel…; CT-2: full
- `phase-4b:77` Copy (⌘C with nothing selected) with a crop: Preview, File >…; CT-2: full
- `phase-4b:92` ⌘C with nothing selected still copies the flattened image… (also `EDPLACE`); CT-2: in part
- `phase-4b:105` Saved capture, never uploaded: Annotate on its row opens the…; CT-2: full
- `phase-4b:106` Capture uploaded with "Upload and copy URL": Annotate on its… (also `EDPLACE`); CT-2: in part
- `phase-4b:107` Upload-only capture whose upload failed: opens from…; CT-2: full
- `phase-4b:108` Upload-only capture that finished uploading: Annotate downloads…; CT-2: full
- `phase-4b:112` Enter a wrong secret access key in Settings > Upload and press… (also `EDPLACE`); CT-2: in part
- `phase-4b:113` The row still copies the old URL. Annotate on the row reopens… (also `EDPLACE`); CT-2: in part
- `phase-4b:114` Enter the right key and press ⌘U: the same URL now serves the…; CT-2: full
- `phase-4c:94` The toolbar shows fourteen tools, in order: Select, Redact… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); CT-2: deferred
- `phase-4c:95` With the canvas focused, `S` (either case) picks Spotlight… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); CT-2: deferred
- `phase-4c:179` Once the upload has finished, reopen the capture with Annotate…; CT-2: full
- `phase-4c:201` Shape and Size survive a relaunch. Choose Ellipse and Large… (also `EDDEFAULTS`); CT-2: in part
- `phase-4c:214` An older capture, made before 4c, opens in the editor, edits…; CT-2: full
- `phase-6a:131` Delete a card in the middle of the stack and Annotate another… (also `QASTACK`); CT-2: in part
- `phase-6a:152` Annotate from a card opens the editor and closes the card (not…; CT-2: full
- `phase-6a:158` Delete a capture from its card, and open the editor from…; CT-2: full
- `phase-6a:164` A restored card's Annotate opens the editor from the file or… (also `SCREENS`); CT-2: in part
- `phase-6a:198` Upload only, after the upload: the card is still on screen, and… (also `SAVEAS`); CT-2: in part
- `phase-6a:199` An edited capture's drag copy is replaced. Upload-only mode… (also `SAVEAS`, `PINS`); CT-2: in part
- `phase-6b:118` action=annotate: the after-capture action runs, then the editor… (also `TARGET`, `PINS`); CT-2: in part
- `phase-7c:72` The toolbar in the editor has a `Background` button (the… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); CT-2: deferred
- `phase-7c:169` Copy (⇧⌘C, or ⌘C with nothing selected, since ⌘C with an… (also `EDPLACE`); moved from A by tests-A (a constructed EditorWindowController); CT-2: in part
- `phase-7c:170` Save (⌘S) on a capture with a local file: the file in the save… (also `EDPLACE`); CT-2: in part
- `phase-7c:171` Annotate the saved capture again: it opens as the composed… (also `EDPLACE`, `BGPOP`); CT-2: in part
- `phase-7c:172` Save As… (⇧⌘S): the file is the composed image; the capture and… (also `EDSAVEAS`); CT-2: in part
- `phase-7c:187` Open the window capture in the editor (the card's Annotate): it… (also `EDPLACE`, `TARGET`, `BGPOP`); CT-2: in part
- `small-tweaks:18` Edit a capture in the editor and Save: its row shows the edited…; CT-2: full

### 2. Editor window placement (`EDPLACE`): 38 lines, 0 alone

- Replaces: Inside `EditorWindowController` (TidyShot/Editor/Window/EditorWindowController.swift): the screen read in `placeWindow` (:123: `NSScreen.screens`, `NSEvent.mouseLocation`, `NSScreen.main`), the display under the window (`displayID`, :321-322), and the Space-change observer on `NSWorkspace.shared.notificationCenter` (:103-106, removed at :500). Until they move, no test can build a controller, so the window's own glue (the unsaved dot, the subtitle as shown, greyed items, key routing, the validation that refuses a shortcut, closing, the toolbar) runs in no test. `EditorToolbarTests.makeEditor` (TidyShotTests/EditorToolbarTests.swift:54-66) builds one today and is fixed with it.
- Shape: An `EditorWindowPlacement` value (`visibleFrame`, `displayID`, `spaceChanges`) passed to `EditorWindowController.init`, `.live` by default; the suite passes a fixed frame, no display and a notification centre of its own.
- Live: `.live` reads the screen under the mouse (else the main screen, else the first), the window's own screen, and `NSWorkspace.shared.notificationCenter`, as the controller does now.
- Effort for the seam: S
- Note: Designed and built in the CT-2 review: `docs/superpowers/notes/2026-10-30-editor-seam/edplace-design.md` sections 2.1, 4 and 8 (its diff, fakes and controller tests, `Test run with 2283 tests in 193 suites passed` in that scratch tree). CT-2 left these lines to it: the 8 it deferred whole and the 30 it marked in part, whose marks name `EDPLACE` (design section 11).

Lines (38):

- `coordinator-split:43` Annotate the newest card, Save, then Upload [+Editor]. After… (also `EDITOR`, in part since CT-2)
- `phase-4a:37` "Upload and copy URL", a large capture with Network Link… (also `EDITOR`, in part since CT-2)
- `phase-4a:56` The toolbar shows, in order: the tools (Select, Redact… (also `EDITOR`, deferred in CT-2)
- `phase-4a:58` With the canvas focused, `V` `D` `X` `B` `R` `A` pick Select… (also `EDITOR`, deferred in CT-2)
- `phase-4a:88` ⌘1 shows the picture at its natural point size and ⌘0 fits it… (also `EDITOR`, deferred in CT-2)
- `phase-4a:94` Saved capture: Redact, ⌘S. The same file in the save folder now… (also `EDITOR`, in part since CT-2)
- `phase-4a:95` Capture uploaded with "Upload and copy URL": ⌘S rewrites the… (also `EDITOR`, in part since CT-2)
- `phase-4a:96` Capture from before Phase 3: ⌘S rewrites its file, with the… (also `EDITOR`, in part since CT-2)
- `phase-4a:97` Upload-only capture that finished uploading: Save is on… (also `EDITOR`, in part since CT-2; and `EDSAVEAS`)
- `phase-4a:99` Lock the saved file (Finder, Get Info, Locked), edit, ⌘S: a Not… (also `EDITOR`, in part since CT-2)
- `phase-4a:102` Saved capture: edit, then ⇧⌘S. The save panel suggests the… (also `EDITOR`, in part since CT-2; and `EDSAVEAS`)
- `phase-4a:106` ⇧⌘S on a saved capture and save over its own file (confirm… (also `EDITOR`, in part since CT-2; and `EDSAVEAS`)
- `phase-4a:107` Edit, ⌘U, and keep drawing before the window closes (slow… (also `EDITOR`, deferred in CT-2; and `BEEP`)
- `phase-4a:119` "Upload and copy URL" with no destination (Forget Credentials… (also `EDITOR`, in part since CT-2; and `TARGET`)
- `phase-4a:120` "Upload and copy URL" with "Also copy image" on: capture… (also `EDITOR`, in part since CT-2; and `TARGET`)
- `phase-4a:123` Capture uploaded with "Upload and copy URL": Redact, then the… (also `EDITOR`, in part since CT-2)
- `phase-4a:124` Upload-only capture that finished uploading: Redact, ⌘U. The… (also `EDITOR`, in part since CT-2)
- `phase-4a:127` Saved capture never uploaded: ⌥⌘U beeps. ⌘U uploads it for the… (also `EDITOR`, in part since CT-2; and `BEEP`)
- `phase-4a:131` Enter a wrong secret access key in Settings > Upload and press… (also `EDITOR`, in part since CT-2)
- `phase-4a:132` Folder change with a bad key: Settings > General, Choose…… (also `EDITOR`, in part since CT-2)
- `phase-4a:133` The same wrong key, ⌘U on an upload-only capture that finished… (also `EDITOR`, in part since CT-2)
- `phase-4a:145` Slow profile, "Upload and copy URL": capture something large… (also `EDITOR`, in part since CT-2; and `EDSAVEAS`, `BEEP`)
- `phase-4a:146` With an editor open, press Delete on its row and leave the… (also `EDITOR`, in part since CT-2; and `BEEP`)
- `phase-4a:147` Delete again and confirm: the subtitle reads This capture was… (also `EDITOR`, in part since CT-2; and `EDSAVEAS`)
- `phase-4a:148` Editor open on a capture in the save folder: Settings >… (also `EDITOR`, in part since CT-2; and `EDSAVEAS`, `CLOSESHEET`)
- `phase-4a:151` ⌘W on an editor with no changes closes it at once.… (also `EDITOR`, deferred in CT-2)
- `phase-4a:162` Quit, set one record's `timestamp` in `history.json` to two… (also `EDITOR`, in part since CT-2; and `EDSAVEAS`)
- `phase-4b:92` ⌘C with nothing selected still copies the flattened image… (also `EDITOR`, in part since CT-2)
- `phase-4b:106` Capture uploaded with "Upload and copy URL": Annotate on its… (also `EDITOR`, in part since CT-2)
- `phase-4b:112` Enter a wrong secret access key in Settings > Upload and press… (also `EDITOR`, in part since CT-2)
- `phase-4b:113` The row still copies the old URL. Annotate on the row reopens… (also `EDITOR`, in part since CT-2)
- `phase-4c:94` The toolbar shows fourteen tools, in order: Select, Redact… (also `EDITOR`, deferred in CT-2)
- `phase-4c:95` With the canvas focused, `S` (either case) picks Spotlight… (also `EDITOR`, deferred in CT-2)
- `phase-7c:72` The toolbar in the editor has a `Background` button (the… (also `EDITOR`, deferred in CT-2)
- `phase-7c:169` Copy (⇧⌘C, or ⌘C with nothing selected, since ⌘C with an… (also `EDITOR`, in part since CT-2)
- `phase-7c:170` Save (⌘S) on a capture with a local file: the file in the save… (also `EDITOR`, in part since CT-2)
- `phase-7c:171` Annotate the saved capture again: it opens as the composed… (also `EDITOR`, in part since CT-2; and `BGPOP`)
- `phase-7c:187` Open the window capture in the editor (the card's Annotate): it… (also `EDITOR`, in part since CT-2; and `TARGET`, `BGPOP`)

### 3. Value capture target (`TARGET`): 34 lines, 26 alone

- Replaces: `CaptureTarget` (TidyShot/Capture/CaptureTarget.swift:5-9: `.display(SCDisplay)`, `.area(rect:display: SCDisplay)`, `.window(SCWindow)`), carried by `CaptureResult` (:59-64) into `AppCoordinator.save(_:intent:)` (AppCoordinator+Save.swift:16). A test cannot build an `SCDisplay` or `SCWindow`, so `save`, the private `persist` (:140), `writeFile` (:243), `writePendingFile` (:263), `copyOnly` (:111) and `withWindowBackground` (:81) are never driven. `save` reads only `target.displayID` (:62, :86), `target.areaRect` (:64) and `case .window` (:82).
- Shape: A value type that replaces the SC* objects: display id and frame, optional area rect, window id and frame. Cheaper form for the save lines alone: an internal `save(image:scale:source:intent:)` over a small value (displayID, areaRect, isWindow) that `save(_:intent:)` forwards to.
- Live: `CaptureEngine` resolves the value back to the `SCDisplay`/`SCWindow` by id in the content it already read when it captures; `save` keeps working on the three fields it reads now.
- Effort for the seam: M (the save-only form); L if it also becomes the type `CAPSRC` passes around

Lines (34):

- `coordinator-split:36` Capture Area: the file, the card and the clipboard [+Capture… (also `SCREENS`, `WORKSPACE`)
- `coordinator-split:42` Retry Failed Uploads with no destination: one notification…
- `phase-1:36` File lands in the chosen folder with the template name…
- `phase-1:39` Cancelling the folder chooser leaves the image on the clipboard… (also `FOLDER`)
- `phase-1:45` Choose… changes the folder and the next capture lands there.
- `phase-2:25` After-capture action "Upload and copy URL": capture, wait for…
- `phase-2:30` With "Also copy image" on: immediately after capture, paste…
- `phase-2:32` After-capture action "Save and copy image": no upload happens…
- `phase-2:33` Delete the "TidyShot S3 credentials" item in Keychain Access… (also `UPLOADFORM`)
- `phase-2:48` Turn Wi-Fi off, capture: the file is saved, the overlay shows…
- `phase-3:48` Forget Credentials, then capture in upload-only: one "Upload…
- `phase-3:49` "Also copy image" on: paste gives the image until the upload…
- `phase-4a:119` "Upload and copy URL" with no destination (Forget Credentials… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-4a:120` "Upload and copy URL" with "Also copy image" on: capture… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-5:179` "Upload only, keep no local file": nothing appears in the save…
- `phase-5:202` history.json has the full pixelWidth and pixelHeight for each…
- `phase-6b:66` All-in-One captures behave like any other in upload-only mode…
- `phase-6b:115` action=upload with General set to Save and copy image: saved…
- `phase-6b:116` action=save under Upload only: saved in the save folder, the…
- `phase-6b:117` action=copy: the image is on the clipboard (Preview > New from…
- `phase-6b:118` action=annotate: the after-capture action runs, then the editor… (also `EDITOR`, `PINS`)
- `phase-7c:117` A window capture with the setting on and Custom Image, then a… (also `BGFILL`)
- `phase-7c:179` Capture Window (⌃⇧2) on a normal window: the saved file, the…
- `phase-7c:182` Not included: Capture Area (⌃⇧4), Capture Fullscreen (⌃⇧3)…
- `phase-7c:184` Padding 0, 160, Corner Radius 0, 40, Shadow off, and each…
- `phase-7c:185` A portrait window (narrower than tall) with 16:9: the canvas is…
- `phase-7c:186` The setting off: a window capture is the plain window again, at…
- `phase-7c:187` Open the window capture in the editor (the card's Annotate): it… (also `EDITOR`, in part since CT-2; and `EDPLACE`, `BGPOP`)
- `phase-7c:188` action=copy: t 'capture-window?action=copy', click a window…
- `phase-7c:189` A window larger than the limit cannot be made, so Background…
- `phase-7c:190` Two window captures in quick succession (the second before the…
- `phase-7c:197` With the setting off and the editor's background off, a window…
- `small-tweaks:13` A screenshot row reads <time> · <size>, for example 2 minutes…
- `small-tweaks:16` An upload-only capture shows a size before and after its upload.

### 4. Capture source (engine and selector) (`CAPSRC`): 34 lines, 8 alone

- Replaces: `let engine = CaptureEngine()` (AppCoordinator.swift:15), read through `loadContent` (:511-523, `engine.shareableContent()`) and `capture(...)`, and `lazy var selector = SelectionController(...)` (:32), whose `select`, `selectAllInOne`, `dismiss`, `overlayWindows`, `frozenCapture` the capture and recording entry points call (+Capture.swift:37-360, +Recording.swift:215-221, :490). Every capture and recording start reads content first, including `capturePreviousArea`'s refusals (+Capture.swift:146-160).
- Shape: Two protocols on `AppEnvironment`: a content source whose `shareableContent()` returns value displays and windows and whose `capture(target:)` returns an image, and a selector whose `select(mode:content:freeze:)` returns a value `Selection`.
- Live: `CaptureEngine` and `SelectionController` conform; the live content source wraps `SCShareableContent` and keeps the SC objects behind the ids.
- Effort for the seam: L
- Note: Built on `TARGET`: the content and the selection carry the value target. Lines that need only the engine half: phase-5:78, phase-6a:209, phase-6a:214, recording-r3:276 and the `recordFullscreen` legs.

Lines (34):

- `phase-5:78` Drag an area 400 pt wide and 60 pt tall: no session starts and… (also `SCROLL`)
- `phase-5:182` Nothing is written or uploaded before Done: during a session… (also `SCROLL`)
- `phase-6a:209` With no stored area (defaults delete io.tky.tidyshot…
- `phase-6a:211` The rect survives a relaunch. A window capture and a fullscreen… (also `SCROLL`)
- `phase-6a:214` An area that leaves less than 1 point on its display is…
- `phase-6b:62` A stored area on a connected display: ⌃⇧1 opens with it… (also `SELINT`); placePreselected is SelectionController's own (SELINT)
- `phase-6b:75` While the countdown runs, ⌃⇧4, the Self-Timer shortcut and the… (also `STAGE`, `STATUSMENU`); STATUSMENU only for the menu half
- `phase-6b:77` 3 seconds and 10 seconds in Settings > Capture count from 3 and… (also `STAGE`)
- `phase-6b:79` A self-timer area becomes the previous area (⌃⇧6 captures it… (also `STAGE`)
- `phase-6b:104` t all-in-one: All-in-One with the last area preselected. t…
- `phase-6b:105` A URL-opened All-in-One needs a touch before a key captures…
- `phase-6b:127` A capture-area URL rect becomes the previous area: ⌃⇧6 captures…
- `phase-6b:159` While a selection is open (⌃⇧4, not released), while a… (also `STAGE`, `SCROLL`); SCROLL for the scrolling-session leg
- `phase-6b:160` for i in 1 2 3; do t capture-window; done: one window selection…
- `phase-7b:81` ⌃⇧6 after a Capture Text captures the previous image area, not…
- `phase-7b:96` Not covered: Capture Scrolling (⌃⇧5) and Capture Text (⌃⇧7)… (also `COVERS`)
- `recording-r1:102` Stop each way, one recording each, whichever way it was… (also `RECCHROME`, `EXTRAS`)
- `recording-r1:105` An area smaller than 32 x 32 pt posts Select a larger area to…
- `recording-r1:122` A window recording with Hide desktop icons while capturing on… (also `COVERS`)
- `recording-r1:124` The covers are gone after Stop, after Cancel and after a… (also `COVERS`, `RECCHROME`, `EXTRAS`, `STAGE`); COVERS alone covers withCaptureLock's show and hide; the Stop, Cancel and count-in exits need the rest
- `recording-r1:196` Closing the window during the count-in, and moving it: closing… (also `STAGE`, `RECCHROME`)
- `recording-r2:231` Two GIF recordings converting at once. Record two 30 s GIFs… (also `RECCHROME`)
- `recording-r2:236` Stop Making GIF with one conversion does the same for that… (also `RECCHROME`)
- `recording-r2:238` Quit during a conversion. Start a 60 s GIF's conversion and… (also `RECCHROME`)
- `recording-r2:351` With the prompt up: a second Record press does nothing and logs… (also `STATUSMENU`, `RECCHROME`); the held-prompt part is A, tested by tests-A's `CoordinatorRecordingTests.aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing` over a held microphone fake
- `recording-r2:390` A GIF save that ends during a second recording, with Show… (also `RECCHROME`)
- `recording-r2:397` The same with the GIF saved during the second recording's… (also `RECCHROME`, `STAGE`)
- `recording-r2:402` The same with an upload that finishes during a recording: an… (also `RECCHROME`)
- `recording-r2:407` Quit during the second recording of the first check: the held… (also `RECCHROME`)
- `recording-r2:409` A quick quit, where nothing else holds the quit. Start the… (also `RECCHROME`, `STAGE`)
- `recording-r2:605` 1. Settings are read at the start: the hand-off reads the… (also `RECCHROME`)
- `recording-r2:653` E. A post-Stop notice during a later recording: every… (also `RECCHROME`)
- `recording-r3:276` A failed content read: not forceable by hand; the code path is… (also `EXTRAS`)
- `recording-r4:217` The record shortcut during the settle delay with Count down… (also `LOG`, deferred in CT-3; and `TMPDIRS`)

### 5. Clop optimiser and running check (`CLOP`): 23 lines, 22 alone

- Replaces: `let clopOptimiser = ClopApp.makeOptimiser()` (AppCoordinator.swift:160; `ClopApp` in TidyShot/Upload/ClopOptimiser.swift:278, over the real `tmp/Clop` and `ClopClient`) and `clopIsRunning()` calling `ClopApp.runningBundleID()` (AppCoordinator+Upload.swift:425-431; NSRunningApplication at ClopOptimiser.swift:267). With `optimiseWithClop` on, a test today depends on whether Clop runs on the test Mac.
- Shape: Built in CT-3 (design 2.1): two members on `AppEnvironment`, `clopOptimiser: any ClopOptimising` and `isClopRunning: @MainActor () -> Bool`. `ClopOptimising` is a protocol of the two calls the coordinator makes (`optimisedPNG`, `optimisedVideo`), and `ClopOptimiser` conforms to it unchanged. A fake transport under the concrete optimiser was rejected: a hold there blocks a thread on the optimiser's two shared static queues and has no cancellation. The running check is a `Bool` because the coordinator reads the bundle id only as nil or not.
- Live: `ClopApp.makeOptimiser()` and `{ ClopApp.runningBundleID() != nil }`.
- Effort for the seam: S
- CT-3: Built on `small-seams` (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`). Each line below carries its CT-3 verdict; a line marked in part also sits under every other seam its mark names, noted there as "also `CLOP`, in part since CT-3".

Lines (23):

- `phase-7-clop:21` The toggle takes effect without Save: turn it on, close…; CT-3: in part
- `phase-7-clop:28` Editor Upload (same link), the same-key replace, Upload as New…; the editor half through `EDITOR` (landed in CT-2); CT-3: full
- `phase-7-clop:29` Upload-only mode (After capture: Upload only, keep no local…; CT-3: full
- `phase-7-clop:31` A capture that Clop cannot shrink (upload a plain white fill…; CT-3: full
- `phase-7-clop:32` A key template with {counter}: three captures in a row get…; CT-3: full
- `phase-7-clop:35` Quit Clop, toggle on, capture: the original uploads, the log…; CT-3: full
- `phase-7-clop:36` Clop set to convert PNG to another format (Clop > Settings >…; CT-3: full
- `phase-7-clop:37` Free-tier Clop past its cap, if you can reach it: uploads still…; CT-3: full
- `phase-7-clop:41` Delete while Clop is optimising a large scrolling capture…; CT-3: full
- `phase-7-clop:42` The same Delete where the record is kept: make the file removal…; CT-3: full
- `phase-7-clop:43` With the file removal made to fail as above, Delete, decline…; CT-3: full
- `phase-7-clop:44` Change upload settings during optimisation: start the 65,536 px…; CT-3: full
- `phase-7-clop:45` Toggle the setting off while an optimisation runs: the running…; CT-3: full
- `recording-r1:271` Delete (and confirm) during the upload cancels it and removes…; CT-3: full
- `recording-r1:296` Cleanup. ls $C/tmp/Clop is empty after an optimised upload… (also `TMPDIRS`); CT-3: in part
- `recording-r1:297` Clop off: the original uploads and the card never says…; CT-3: full
- `recording-r1:330` 3. Counter: for a recording's upload, {counter} is drawn after…; CT-3: full
- `recording-r2:275` Clop on and running, then a GIF: it uploads as made. The card…; CT-3: in part
- `recording-r4:253` Clop on, Upload Trimmed on a trimmed file over 100 MiB, fail it…; CT-3: in part
- `recording-r4:255` A Clop result kept in multipart/<id>.mp4 is used by Retry (no…; CT-3: full
- `recording-r4:323` 16. Clop's result is kept in multipart/<id>.mp4, and a Retry…; CT-3: full
- `small-tweaks:14` Upload a capture with Clop on: after the upload, the row shows…; CT-3: full
- `small-tweaks:15` A recording row shows its size after it saves, and the…; CT-3: full

### 6. Card Save As panel (`SAVEAS`): 14 lines, 7 alone

- Replaces: `askSaveAsTarget` (TidyShot/App/AppCoordinator+RecordActions.swift:195-206): `EditorNaming.savePanel(for:)` and `await panel.begin()`, reached from `saveAs(recordID:)` (:111) -> `saveCopy` (:179) and from `saveVideoCopy` (:130).
- Shape: A closure on `AppEnvironment`: `chooseSaveAsURL: @MainActor (EditorNaming.SaveAsSuggestion) async -> URL?`. A held answer (the `FakeConfirm` pattern) covers phase-6a:175.
- Live: Builds `EditorNaming.savePanel(for:)`, activates the app and awaits `panel.begin()`, as the body does now.
- Effort for the seam: S
- CT-3: Built on `small-seams` (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`). Each line below carries its CT-3 verdict; a line marked in part also sits under every other seam its mark names, noted there as "also `SAVEAS`, in part since CT-3".

Lines (14):

- `coordinator-split:44` Pin, then the pin menu's three items [+Pins, +RecordActions]… (also `PINS`, `SCREENS`, `EDITOR`); CT-3: in part
- `phase-6a:170` Save to the Desktop: shasum -a 256 of the copy equals that of…; CT-3: in part
- `phase-6a:171` For an upload-only capture the suggestion is the file name…; CT-3: in part
- `phase-6a:172` After the upload, on a card that showed through it: the panel… (also `SCREENS`); also FakeDestination.download(key:) able to throw; CT-3: in part
- `phase-6a:174` Save As… changes nothing about the capture: the card, its link…; CT-3: full
- `phase-6a:175` Open the panel and wait for the card's auto-close to run out…; CT-3: in part
- `phase-6a:176` Use Save As… from the button and from the context menu, from a… (also `SCREENS`); CT-3: in part
- `phase-6a:198` Upload only, after the upload: the card is still on screen, and… (also `EDITOR`); CT-3: in part
- `phase-6a:199` An edited capture's drag copy is replaced. Upload-only mode… (also `EDITOR`, in part since CT-2; and `PINS`); CT-3: in part
- `recording-r1:313` Restoring an uploaded upload-only video's card after its drag… (also `SCREENS`); CT-3: in part
- `recording-r1:340` A screenshot's save, upload, Retry, Delete, Save As… and Copy…; CT-3: full
- `recording-r2:264` A GIF's card and row. The card has the poster with a GIF badge… (also `WORKSPACE`); CT-3: in part
- `recording-r2:670` A screenshot's save, upload, Retry, Delete, Save As… and Copy…; CT-3: full
- `recording-r4:277` Save As… during the download waits and then saves the landed…; CT-3: full

### 7. Recording chrome factory (`RECCHROME`): 14 lines, 0 alone

- Replaces: `RecordingScreenChrome(placement:extras:)` at the end of `recordingHandOff` (TidyShot/App/AppCoordinator+Recording.swift:582), which `recorder.run` shows (RecordingController.swift:197). Together with `CAPSRC` it lets `recordScreen`/`recordFullscreen` -> `record()` (+Recording.swift:397) -> `endRecording` (:623: `makeGIF`, `muteAndSave`, `saveRecording`) and the notice hold run over `FakeRecordingDriver`.
- Shape: A closure on `AppEnvironment`: `makeRecordingChrome(placement, extras) -> any RecordingChrome`. The `RecordingChrome` protocol exists.
- Live: `RecordingScreenChrome` conforms already.
- Effort for the seam: S
- Note: An area or fullscreen recording also builds `RecordingExtras` (`EXTRAS`); a window recording does not, so the lines below can be written over a window recording. A count-in needs `STAGE`, or `recordingCountdown` off and the settle delay on the world's clock.

Lines (14):

- `recording-r1:102` Stop each way, one recording each, whichever way it was… (also `CAPSRC`, `EXTRAS`)
- `recording-r1:124` The covers are gone after Stop, after Cancel and after a… (also `COVERS`, `CAPSRC`, `EXTRAS`, `STAGE`); COVERS alone covers withCaptureLock's show and hide; the Stop, Cancel and count-in exits need the rest
- `recording-r1:196` Closing the window during the count-in, and moving it: closing… (also `CAPSRC`, `STAGE`)
- `recording-r2:231` Two GIF recordings converting at once. Record two 30 s GIFs… (also `CAPSRC`)
- `recording-r2:236` Stop Making GIF with one conversion does the same for that… (also `CAPSRC`)
- `recording-r2:238` Quit during a conversion. Start a 60 s GIF's conversion and… (also `CAPSRC`)
- `recording-r2:351` With the prompt up: a second Record press does nothing and logs… (also `STATUSMENU`, `CAPSRC`); the held-prompt part is A, tested by tests-A's `CoordinatorRecordingTests.aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing` over a held microphone fake
- `recording-r2:390` A GIF save that ends during a second recording, with Show… (also `CAPSRC`)
- `recording-r2:397` The same with the GIF saved during the second recording's… (also `CAPSRC`, `STAGE`)
- `recording-r2:402` The same with an upload that finishes during a recording: an… (also `CAPSRC`)
- `recording-r2:407` Quit during the second recording of the first check: the held… (also `CAPSRC`)
- `recording-r2:409` A quick quit, where nothing else holds the quit. Start the… (also `CAPSRC`, `STAGE`)
- `recording-r2:605` 1. Settings are read at the start: the hand-off reads the… (also `CAPSRC`)
- `recording-r2:653` E. A post-Stop notice during a later recording: every… (also `CAPSRC`)

### 8. Screen list for the card stack and pins (`SCREENS`): 14 lines, 6 alone

- Replaces: `overlayScreen(captureDisplayID:)` (TidyShot/App/AppCoordinator+Overlay.swift:55-62: `NSScreen.screens`, `NSEvent.mouseLocation`), used by `showOverlay` and by `restoreClosedOverlay` when `overlay.screen` is nil (:94, which `FakeCards.screen` always is); `pinScreen(preferred:)` (AppCoordinator+Pins.swift:58-64) and `pin`'s primary height (:31). `QuickAccessCards.show(record:thumbnail:screen: NSScreen, ...)` (QuickAccessController.swift:387) takes an `NSScreen`, which a test cannot make.
- Shape: A closure on `AppEnvironment` returning value screens (display id, frame, visible frame) plus the pointer location, and `QuickAccessCards.show` taking a screen value (or a display id) instead of an `NSScreen`.
- Live: `NSScreen.screens` mapped to values and `NSEvent.mouseLocation`; `QuickAccessController.show` looks the `NSScreen` up by display id, as `stackScreen()` already does (QuickAccessController.swift:337).
- Effort for the seam: M

Lines (14):

- `coordinator-split:36` Capture Area: the file, the card and the clipboard [+Capture… (also `TARGET`, `WORKSPACE`)
- `coordinator-split:44` Pin, then the pin menu's three items [+Pins, +RecordActions]… (also `PINS`, `SAVEAS`, `EDITOR`)
- `coordinator-split:46` Restore Closed Overlay [+Overlay, and init's…
- `phase-6a:160` Restore walks back through the closed list even when the stack…; also a FakeCards that pushes the oldest card out past a limit
- `phase-6a:161` The list holds ten: set Show up to 1 and take twelve captures…
- `phase-6a:164` A restored card's Annotate opens the editor from the file or… (also `EDITOR`, in part since CT-2)
- `phase-6a:172` After the upload, on a card that showed through it: the panel… (also `SAVEAS`, in part since CT-3)
- `phase-6a:176` Use Save As… from the button and from the context menu, from a… (also `SAVEAS`, in part since CT-3)
- `phase-6a:203` Close after dragging out on: a drop onto a receiver closes the…
- `phase-6b:83` Pin a window or fullscreen capture: centred on the pointer's… (also `PINS`)
- `recording-r1:308` R4 changed this (was: cannot be dragged). Dragging an uploaded…
- `recording-r1:313` Restoring an uploaded upload-only video's card after its drag… (also `SAVEAS`)
- `recording-r1:314` Restore Closed Overlay brings back a video's card with its…; also a FakeCards.show that keeps the poster
- `recording-r4:275` A click on the thumbnail opens the link and downloads nothing… (also `WORKSPACE`)

### 9. tmp/ directory statics (`TMPDIRS`): 13 lines, 7 alone

- Replaces: `Recording.directory`/`Recording.makeDirectory()` (TidyShot/Recording/Recording.swift:51, :57), `MuteLog.directory` (MuteLog.swift:24), `RecordingTrim.directory` (RecordingTrim.swift:50), `ClopApp.workDirectory` (ClopOptimiser.swift:272), all under the host's real `FileManager.default.temporaryDirectory`. Read at AppCoordinator.swift:298-300 and :321-322 (start), AppCoordinator+Recording.swift:356-363 (`recordingCanStart`), +Recovery.swift:119 and :165, +Trim.swift:67. `RecordingMute` also reads `MuteLog.directory` itself (RecordingMute.swift:60, :136).
- Shape: Four URLs on `AppEnvironment`, derived from `temporaryDirectory` as `dragFiles` already is, passed to the statics' callers (and to `RecordingMute`/`RecordingTrim` helpers that take a folder default today).
- Live: The same four paths under `FileManager.default.temporaryDirectory`.
- Effort for the seam: M

Lines (13):

- `coordinator-harness:50` 7. pending/ orphans adopted, never deleted; by record id… (also `LAUNCH`)
- `coordinator-harness:69` D27. start()'s one task runs RecordingRecovery.begin (the… (also `LAUNCH`)
- `recording-r1:296` Cleanup. ls $C/tmp/Clop is empty after an optimised upload… (also `CLOP`)
- `recording-r1:328` 1. Free space: tmp/Recording is created just before the 2 GB…
- `recording-r1:333` 6. Strings: <reason> The recording is still at <path>. when…
- `recording-r2:241` `kill -9` during a conversion (`pkill -9 -x TidyShot`), then…; moved from A by tests-A (seam S7 there)
- `recording-r2:320` **(Debug)** kill -9 during a muted recording, then relaunch… (also `MUTESTEPS`)
- `recording-r2:323` kill -9 (a) during a recording while muted, (b) just after…
- `recording-r2:625` 9. Trim: the download posts Downloading <key> under Opening the…; also FakeDestination.download(key:to:) able to throw (today a no-op); TRIM for the method part
- `recording-r3:161` With Show webcam bubble off, a start never prompts for the…
- `recording-r3:407` 1. The camera resolve takes no toggle and runs at every start…
- `recording-r4:217` The record shortcut during the settle delay with Count down… (also `LOG`, deferred in CT-3; and `CAPSRC`)
- `recording-r4:326` 18. No upload resumes by itself at launch. ______ (also `LAUNCH`)

Also the second half of one A line, not counted above: `recording-r2:364` With access undecided and another capture under way… Once the capture is done, a Record press prompts and goes on into `recordingCanStart`, which makes the live `tmp/Recording` (`Recording.makeDirectory`, AppCoordinator+Recording.swift:356). The first half is A, covered in part by tests-A's `CoordinatorRecordingTests.aRecordPressDuringACaptureWithAccessUndecidedShowsNoPrompt`.

### 10. RecordingLog sink (`LOG`): 12 lines, 7 alone

- Replaces: `RecordingLog.note` (TidyShot/Recording/ScreenRecordingDriver.swift:91-96, a static `Logger` the suite cannot read). The coordinator's calls: AppCoordinator+Recording.swift:109-892 (the `stop-recording`, URL-start, prompt and Settings-prompt lines), +Recovery.swift:127-161, +Upload.swift:378, :395. Outside the coordinator: RecordingRecovery.swift:34, :36, :137 (`could not be played, removed` and its failures), RecordingExtras.swift:215-250 (camera lines).
- Shape: Built in CT-3 (design 2.3): a closure on `AppEnvironment` (`recordingLog: @Sendable (String) -> Void`) that the coordinator uses for its own 24 calls and hands to `RecordingRecovery.scan` through `begin`'s `scanning:` parameter; the world collects it as `recordingLines`, beside `logLines`, because `RecordingLog` writes `.public` and `log` does not. `RecordingExtras.init` and the mute sweep are not threaded (`EXTRAS`). A settable static sink would mix lines across parallel suites.
- Live: `RecordingLog.note`.
- Effort for the seam: S for the coordinator's calls; M with the `RecordingRecovery` and `RecordingExtras` ones
- CT-3: Built on `small-seams` (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`). Each line below carries its CT-3 verdict; a line marked in part or deferred also sits under every other seam its mark names, noted there as "also `LOG`, in part since CT-3" or "deferred in CT-3".

Lines (12):

- `coordinator-harness:27` 4. stop-recording's log lines in each phase (R4 checklist…; CT-3: full
- `recording-r1:263` A leftover that does not play (echo junk >…; CT-3: full
- `recording-r3:156` With the camera prompt up: a second Record press does nothing…; CT-3: full
- `recording-r3:162` The microphone pick during a recording behaves as the bubble…; CT-3: in part
- `recording-r3:416` 7. The recording's clock times the camera's log lines and the… (also `EXTRAS`); CT-3: deferred
- `recording-r3:419` 9. The prompts' order and log lines are as the Camera prompt… (also `URLLOG`); CT-3: in part
- `recording-r3:436` D. Recording: camera could not be started: <reason> is logged… (also `EXTRAS`); CT-3: deferred
- `recording-r4:192` Two record-screen URLs back to back (one Keyboard Maestro… (also `URLLOG`); one start and no notice are A now; CT-3: in part
- `recording-r4:214` Turn Show webcam bubble on in Settings while a GIF converts…; CT-3: in part
- `recording-r4:217` The record shortcut during the settle delay with Count down… (also `CAPSRC`, `TMPDIRS`); CT-3: deferred
- `recording-r4:347` 5. RecordingController.isEnding, so a second stop-recording…; CT-3: full
- `recording-r4:366` 18. urlRecordingStartPending makes a second record-screen…; CT-3: full

### 11. Trim window factory (`TRIM`): 11 lines, 9 alone

- Replaces: `TrimWindowController(recordID:fileURL:title:pixelSize:)` in the private `presentTrimWindow` (TidyShot/App/AppCoordinator+Trim.swift:84-103) and the `trimWindows` map; `trimRangeChosen` -> `startTrimPass` -> `runTrimPass` -> `finishTrimWrite` drive that controller (`askToSave`, `showProgress`, `setProgress`, `setStopEnabled`, `close`).
- Shape: A closure on `AppEnvironment` returning a protocol with `present`, `close`, `askToSave(message:informativeText:...)`, `showProgress(onStop:)`, `setProgress`, `setStopEnabled`, `hideProgress`, and the `onRange`/`onFailure`/`onClose` callbacks.
- Live: `TrimWindowController` conforms (TidyShot/Trim/TrimWindowController.swift:15-19, :74, :149-193).
- Effort for the seam: L

Lines (11):

- `recording-r2:433` Settings while a card shows a recording: forget the credentials…
- `recording-r2:442` After a Save: the card's poster, the row's thumbnail, the…
- `recording-r2:444` When the trimmed file's first frame cannot be read, the card… (also `POSTER`)
- `recording-r2:448` Save, Save and Upload (the link plays the trimmed video), an…
- `recording-r2:455` A trim that only moves the end: saved at once after the save…
- `recording-r2:468` Delete the record while its Trim window is open: the window…
- `recording-r2:470` Settings > Upload during a Save and Upload's Trimming… (a 4K…
- `recording-r2:492` Close the Trim window during a passthrough's Save and Upload…
- `recording-r2:495` Rarer paths, if they can be made: Stop during a marked record's…
- `recording-r2:655` F. A close during a passthrough's put lets the pass finish, its…
- `recording-r2:663` J. The card shows the row's placeholder when the trimmed file's… (also `POSTER`)

### 12. Editor Save As sheet (`EDSAVEAS`): 11 lines, 2 alone

- Replaces: `EditorWindowController.performSaveAs()` (TidyShot/Editor/Window/EditorWindowController.swift:259-264): `EditorNaming.savePanel` and `panel.beginSheetModal(for: window)`.
- Shape: A closure passed to `EditorWindowController.init`: `chooseSaveURL: (SaveAsSuggestion) async -> URL?`.
- Live: The sheet as it is.
- Effort for the seam: S

Lines (11):

- `phase-4a:97` Upload-only capture that finished uploading: Save is on… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-4a:102` Saved capture: edit, then ⇧⌘S. The save panel suggests the… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-4a:104` Cancel in the panel: nothing is written and the unsaved dot…
- `phase-4a:106` ⇧⌘S on a saved capture and save over its own file (confirm… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-4a:145` Slow profile, "Upload and copy URL": capture something large… (also `EDITOR`, in part since CT-2; and `EDPLACE`, `BEEP`)
- `phase-4a:147` Delete again and confirm: the subtitle reads This capture was… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-4a:148` Editor open on a capture in the save folder: Settings >… (also `EDITOR`, in part since CT-2; and `EDPLACE`, `CLOSESHEET`)
- `phase-4a:153` On an upload-only capture that finished uploading, the first… (also `CLOSESHEET`)
- `phase-4a:162` Quit, set one record's `timestamp` in `history.json` to two… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-7c:172` Save As… (⇧⌘S): the file is the composed image; the capture and… (also `EDITOR`)
- `phase-7c:174` Each of these twice in a row after a change: no stale result…

### 13. Headless pins (`PINS`): 10 lines, 5 alone

- Replaces: `lazy var pins = PinController()` (AppCoordinator.swift:138). `PinController.open` builds a `PinPanel` and `PinView` and orders the panel front (TidyShot/Pin/PinController.swift:42-88); `lock`, `unlockAll`, `closeAll`, the opacity and zoom closures act on that panel (:94-131).
- Shape: A panel factory inside `PinController` (a protocol over the frame, `orderFrontRegardless`, `ignoresMouseEvents`, `alphaValue`, `close`, `screen`), with the test assigning `coordinator.pins = PinController(makePanel:)`. That covers the coordinator side (`pin`, Delete, prune, `hasPins`) and the controller's own closures (phase-6b:87, :88, :89). A `Pinning` protocol over `PinController` alone covers only the coordinator side.
- Live: `PinPanel(contentRect:)` conforms.
- Effort for the seam: M
- Note: `pin(recordID:)` also reads the screens (`SCREENS`) for where the pin opens.

Lines (10):

- `coordinator-split:44` Pin, then the pin menu's three items [+Pins, +RecordActions]… (also `SCREENS`, `SAVEAS`, `EDITOR`)
- `coordinator-split:49` Retention pruning of a pinned upload-only capture that has…
- `phase-6a:199` An edited capture's drag copy is replaced. Upload-only mode… (also `SAVEAS`, in part since CT-3; and `EDITOR`)
- `phase-6b:83` Pin a window or fullscreen capture: centred on the pointer's… (also `SCREENS`)
- `phase-6b:87` Click the pin, then: arrows move it 1 pt, Shift-arrows 10 pt…; FakeClipboard keeping the PNG bytes, for the pixel size
- `phase-6b:88` Right-click: Copy Image, Save As…, Annotate, Opacity (100%…
- `phase-6b:89` Lock: the border goes and clicks pass through to the app… (also `STATUSMENU`)
- `phase-6b:91` Delete the capture (card, Recent Captures): its pins close…
- `phase-6b:92` A capture pruned by retention closes its pins: set Overlay >…
- `phase-6b:118` action=annotate: the after-capture action runs, then the editor… (also `TARGET`, `EDITOR`)

### 14. RecordingExtras window and camera factories (`EXTRAS`): 9 lines, 4 alone

- Replaces: `RecordingExtras.show(at:)` builds a `ClickRingOverlay` and a `WebcamBubblePanel` and orders both front (TidyShot/Recording/RecordingExtras.swift:86-112); `runCamera` builds a `CameraSession` (:194-196). The coordinator builds `RecordingExtras` for every area or fullscreen recording (AppCoordinator+Recording.swift:438-450).
- Shape: Factories on `RecordingExtras.init` (`makeOverlay`, `makeBubble`, `makeSession`) returning protocols, with the coordinator passing live ones from `AppEnvironment`.
- Live: `ClickRingOverlay`, `WebcamBubblePanel`, `CameraSession` conform.
- Effort for the seam: M

Lines (9):

- `recording-r1:102` Stop each way, one recording each, whichever way it was… (also `CAPSRC`, `RECCHROME`)
- `recording-r1:124` The covers are gone after Stop, after Cancel and after a… (also `COVERS`, `CAPSRC`, `RECCHROME`, `STAGE`); COVERS alone covers withCaptureLock's show and hide; the Stop, Cancel and count-in exits need the rest
- `recording-r3:276` A failed content read: not forceable by hand; the code path is… (also `CAPSRC`)
- `recording-r3:365` A start with the toggle on and a camera that cannot start (not…
- `recording-r3:416` 7. The recording's clock times the camera's log lines and the… (also `LOG`)
- `recording-r3:425` 14. Only a drag's end writes the bubble's place; a size step…
- `recording-r3:433` B. The preview layer exists whenever the camera is usable, so a…
- `recording-r3:435` C. A camera that starts again after a loss counts as the…
- `recording-r3:436` D. Recording: camera could not be started: <reason> is logged… (also `LOG`)

### 15. Self-timer stage factory (`STAGE`): 9 lines, 1 alone

- Replaces: `SelfTimerScreenStage(subject:screenFrame:showsFrame:)` built in `runSelfTimer` (TidyShot/App/AppCoordinator+Capture.swift:297-307, after `NSApplication.shared.deactivate()`) and in the recording count-in (AppCoordinator+Recording.swift:510-516), with the frame from `CaptureEngine.screen(forDisplayID:) ?? NSScreen.main`. The stage's `init` makes its panels (SelfTimerPanel.swift:62-73).
- Shape: A closure on `AppEnvironment`: `makeSelfTimerStage(subject, screenFrame, showsFrame) -> any SelfTimerStage`, plus the screen-frame lookup for a display id. The `SelfTimerStage` protocol and `FakeSelfTimerStage` exist (SelfTimerController.swift:14, SelfTimerTests.swift:9).
- Live: `SelfTimerScreenStage` conforms already; the frame comes from `CaptureEngine.screen(forDisplayID:)`.
- Effort for the seam: S

Lines (9):

- `phase-6b:75` While the countdown runs, ⌃⇧4, the Self-Timer shortcut and the… (also `CAPSRC`, `STATUSMENU`); STATUSMENU only for the menu half
- `phase-6b:76` A rect near the top-right corner of the screen: the badge stays…
- `phase-6b:77` 3 seconds and 10 seconds in Settings > Capture count from 3 and… (also `CAPSRC`)
- `phase-6b:79` A self-timer area becomes the previous area (⌃⇧6 captures it… (also `CAPSRC`)
- `phase-6b:159` While a selection is open (⌃⇧4, not released), while a… (also `CAPSRC`, `SCROLL`); SCROLL for the scrolling-session leg
- `recording-r1:124` The covers are gone after Stop, after Cancel and after a… (also `COVERS`, `CAPSRC`, `RECCHROME`, `EXTRAS`); COVERS alone covers withCaptureLock's show and hide; the Stop, Cancel and count-in exits need the rest
- `recording-r1:196` Closing the window during the count-in, and moving it: closing… (also `CAPSRC`, `RECCHROME`)
- `recording-r2:397` The same with the GIF saved during the second recording's… (also `CAPSRC`, `RECCHROME`)
- `recording-r2:409` A quick quit, where nothing else holds the quit. Start the… (also `CAPSRC`, `RECCHROME`)

### 16. Status menu model (`STATUSMENU`): 8 lines, 5 alone

- Replaces: `StatusMenuController` (TidyShot/App/StatusMenuController.swift): `NSStatusBar.system.statusItem` in `init` (:20), the inline symbol choice in `updateIcon` (:42-60), and the private `rebuild()` (:75) with `KeyboardShortcuts` titles and `ScreenCapturePermission`.
- Shape: Pure functions of coordinator state: `rebuild`'s item list as values (title, enabled, checked, action) and `static symbol(recording:uploading:)`; or the `NSStatusItem` injected so a test can call `menuNeedsUpdate` on an item that is not in the menu bar.
- Live: `StatusMenuController` builds its `NSMenu` and icon from the values.
- Effort for the seam: M

Lines (8):

- `phase-2:27` The menu bar icon shows an up-arrow circle while uploading and…
- `phase-3-1:22` With a failed upload in history, Retry Failed Uploads retries…
- `phase-6b:46` The menu bar menu reads All-in-One  ⌃⇧1, Capture Area  ⌃⇧4…
- `phase-6b:75` While the countdown runs, ⌃⇧4, the Self-Timer shortcut and the… (also `CAPSRC`, `STAGE`); STATUSMENU only for the menu half
- `phase-6b:89` Lock: the border goes and clicks pass through to the app… (also `PINS`)
- `recording-r1:85` The menu bar menu has Record Screen  ⌃⇧8 and Record Fullscreen…
- `recording-r2:351` With the prompt up: a second Record press does nothing and logs… (also `CAPSRC`, `RECCHROME`); the held-prompt part is A, tested by tests-A's `CoordinatorRecordingTests.aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing` over a held microphone fake
- `recording-r2:616` 5. The GIF menu items come first in the status menu, after Stop…

### 17. Background popover state (`BGPOP`): 7 lines, 5 alone

- Replaces: `BackgroundPopoverView` (TidyShot/Editor/Window/BackgroundPopoverView.swift:9-51) reads `AppSettings.shared.backgroundStyle` (:38, :43, :47) and keeps its on, fits and style bindings private.
- Shape: The bindings moved to an internal state type (or `EditorModel`) that takes an `AppSettings`.
- Live: The view builds the state over `AppSettings.shared`.
- Effort for the seam: M

Lines (7):

- `phase-7c:84` The popover's first row is a Background switch, off, with the…
- `phase-7c:86` Turn the switch off: the capture is as it was, the style editor…
- `phase-7c:87` Turn it on again after changing the Capture tab's style: it…
- `phase-7c:97` After an undo that removes the background, the popover's switch…
- `phase-7c:148` A second scrolling capture of about 9,000 pt (18,000 px): open…
- `phase-7c:171` Annotate the saved capture again: it opens as the composed… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-7c:187` Open the window capture in the editor (the card's Annotate): it… (also `EDITOR`, in part since CT-2; and `EDPLACE`, `TARGET`)

### 18. Quick Access stack internals (`QASTACK`): 6 lines, 5 alone

- Replaces: Inside `QuickAccessController` (TidyShot/Overlay/QuickAccessController.swift): `QuickAccessPanel(model:)` (:74), `stackScreen()` over `NSScreen` (:337), `NSEvent.mouseLocation` (:307, :366) and `Task.sleep` (:315, :361) in `watchPointer` and `scheduleClose`.
- Shape: Factories passed to `QuickAccessController.init`: a panel protocol (frame, orderFront, orderOut), a screen provider (display id, visible frame), a pointer-location closure, and a `ScrollClock` for the sleeps.
- Live: `QuickAccessPanel`, `NSScreen`, `NSEvent.mouseLocation`, `SystemScrollClock`.
- Effort for the seam: L

Lines (6):

- `phase-6a:127` Auto-close 5 s: every card closes by its own timer, the oldest…
- `phase-6a:128` A card that slides away from a still pointer closes. Auto-close…
- `phase-6a:129` Lowering Show up to N overlays takes effect at the next layout…
- `phase-6a:130` While the pointer is over a card, let another card close: the…
- `phase-6a:131` Delete a card in the middle of the stack and Annotate another… (also `EDITOR`)
- `phase-6a:132` Upload-only mode, a capture uploading in one card and an older…

### 19. Upload settings form model (`UPLOADFORM`): 6 lines, 5 alone

- Replaces: `UploadSettingsView` (TidyShot/Settings/UploadSettingsView.swift:6) reads `AppCoordinator.shared` and keeps `load()`, `save()`, `forgetCredentials()`, `test()` private on the view (:112, :128, :158, :174). `Saved.` and the joined test status exist only there.
- Shape: A value type replacing no SC object: an `@Observable` form model over an `AppCoordinator` (fields, `statusMessage`, `statusIsError`, `keychainError`) with `load`, `save`, `forgetCredentials`, `test`; the view binds to it.
- Live: The view builds the model over `AppCoordinator.shared`.
- Effort for the seam: M

Lines (6):

- `phase-2:12` Fill in endpoint, region, bucket, public URL…
- `phase-2:16` defaults read io.tky.tidyshot does not contain the access key…
- `phase-2:19` Save and Test Connection with a key that may PUT but not DELETE…
- `phase-2:33` Delete the "TidyShot S3 credentials" item in Keychain Access… (also `TARGET`)
- `phase-3:54` Template {date}/{hostname}: the orange warning appears and says…
- `phase-3:56` Template my shots/{random}: red message " " is not allowed……

### 20. Desktop covers behind a protocol (`COVERS`): 6 lines, 3 alone

- Replaces: `lazy var covers = DesktopCoverController(source: WallpaperSource(), reportFailure:)` (AppCoordinator.swift:61-68), whose `show` reaches ScreenCaptureKit, `NSScreen` and `NSPanel`. Called at AppCoordinator.swift:48, :329, :382-384, :572-574 (`withCaptureLock`), +Capture.swift:58, +Recording.swift:229.
- Shape: A `DesktopCovering` protocol (`show(for:) async`, `hide(for:)`, `isPersistent`, `windowNumbers`) from `AppEnvironment`, with a recording fake.
- Live: `DesktopCoverController` conforms.
- Effort for the seam: S

Lines (6):

- `phase-7b:96` Not covered: Capture Scrolling (⌃⇧5) and Capture Text (⌃⇧7)… (also `CAPSRC`)
- `phase-7b:101` The toggle off: no capture covers anything.
- `phase-7b:121` t hide-desktop-icons: covered, the menu item checked. t…
- `recording-r1:122` A window recording with Hide desktop icons while capturing on… (also `CAPSRC`)
- `recording-r1:124` The covers are gone after Stop, after Cancel and after a… (also `CAPSRC`, `RECCHROME`, `EXTRAS`, `STAGE`); COVERS alone covers withCaptureLock's show and hide; the Stop, Cancel and count-in exits need the rest
- `recording-r1:125` A recording started with the setting off shows the icons.

### 21. Launch steps out of start() (`LAUNCH`): 6 lines, 3 alone

- Replaces: `AppCoordinator.start()` (TidyShot/App/AppCoordinator.swift:294-336) is not driven: it removes `ClopApp.workDirectory` and `RecordingTrim.directory` (:298-300), registers `KeyboardShortcuts`, reads `ScreenCapturePermission.isGranted` and shows the permission window (:331-333). Its file steps are the drag sweep (:296), the multipart sweep (:307-312), the private `backfillByteCounts` (:314, declared :342) and the recovery task `RecordingRecovery.begin` -> `adoptPendingFiles` -> `recoverRecordings` (:320-325).
- Shape: Methods moved out of `start()`: an internal `launchFileSteps()` or separate internal `launchSweeps()`, `backfillByteCounts()`, `launchRecovery(pendingListed:)`, which `start()` calls in the same order.
- Live: `start()` calls the extracted methods, then `registerShortcuts()`, the covers, the permission window and `urlCommands.ready()` as now.
- Effort for the seam: S
- Note: The recovery step and the tmp/Clop and tmp/Trim removals read the directory statics (`TMPDIRS`).

Lines (6):

- `coordinator-harness:50` 7. pending/ orphans adopted, never deleted; by record id… (also `TMPDIRS`)
- `coordinator-harness:69` D27. start()'s one task runs RecordingRecovery.begin (the… (also `TMPDIRS`)
- `phase-6a:205` Delete the capture whose card was dragged from: its…
- `recording-r4:262` The files in multipart/ of a record with no state, or a state…
- `recording-r4:326` 18. No upload resumes by itself at launch. ______ (also `TMPDIRS`)
- `small-tweaks:20` A capture saved before this change shows a size after relaunch…

### 22. Scrolling capture behind a protocol (`SCROLL`): 6 lines, 2 alone

- Replaces: `lazy var scrollCapture = ScrollCaptureController(engine:settings:)` (AppCoordinator.swift:33); the coordinator calls `isRunning` and `advance()` (+Capture.swift:82-83), `run(rect:display:makesPanelKey:readyTimeout:)` (:128) and `cancel()` (AppCoordinator.swift:437).
- Shape: A protocol with those four members, held by the coordinator, with a fake that scripts the `ScrollCaptureOutcome` and records `advance`/`cancel`.
- Live: `ScrollCaptureController` conforms.
- Effort for the seam: S

Lines (6):

- `phase-5:78` Drag an area 400 pt wide and 60 pt tall: no session starts and… (also `CAPSRC`)
- `phase-5:80` While a session is open (panel on screen), the menu's Capture…
- `phase-5:97` Click Start and Done at once without scrolling: a single-frame…
- `phase-5:182` Nothing is written or uploaded before Done: during a session… (also `CAPSRC`)
- `phase-6a:211` The rect survives a relaunch. A window capture and a fullscreen… (also `CAPSRC`)
- `phase-6b:159` While a selection is open (⌃⇧4, not released), while a… (also `CAPSRC`, `STAGE`); SCROLL for the scrolling-session leg

### 23. Workspace open and reveal (`WORKSPACE`): 6 lines, 2 alone

- Replaces: `NSWorkspace.shared.open` in `openCapture(recordID:)` (TidyShot/App/AppCoordinator+RecordActions.swift:60, :71), `activateFileViewerSelecting` in `reveal(recordID:)` (:275) and Reveal Last Capture (AppCoordinator+Capture.swift:371).
- Shape: Two closures on `AppEnvironment`: `open: (URL) -> Void` and `reveal: ([URL]) -> Void`.
- Live: `NSWorkspace.shared.open` and `activateFileViewerSelecting`.
- Effort for the seam: S

Lines (6):

- `coordinator-split:36` Capture Area: the file, the card and the clipboard [+Capture… (also `TARGET`, `SCREENS`)
- `phase-2:41` Clicking the thumbnail reveals the file in Finder.
- `recording-r1:302` A card for an upload-only video that finished: a click opens…
- `recording-r1:303` A card for a temporary file with .none shows Kept in TidyShot… (also `FOLDER`)
- `recording-r2:264` A GIF's card and row. The card has the poster with a GIF badge… (also `SAVEAS`)
- `recording-r4:275` A click on the thumbnail opens the link and downloads nothing… (also `SCREENS`)

### 24. Editor export beep (`BEEP`): 5 lines, 1 alone

- Replaces: `NSSound.beep()` in the editor window (widened by CT-2, design call 12): `export`'s failure path (TidyShot/Editor/Window/EditorWindowController.swift:314), the beep while another document action runs (:236), `performUpload`'s when the drawing changed during the call (:280), `askToSaveBeforeClosing`'s (:464), and `EditorWindow.send`'s when the window's validation refuses a shortcut (TidyShot/Editor/Window/EditorWindow.swift:45). The refusal itself is the validation's (`EDPLACE`); `CanvasView`'s two beeps (CanvasView.swift:364, :439) stay.
- Shape: A `beep` closure on `EditorWindowController.init`, handed to its `EditorWindow`.
- Live: `NSSound.beep()`.
- Effort for the seam: S

Lines (5):

- `phase-4a:107` Edit, ⌘U, and keep drawing before the window closes (slow… (also `EDITOR`, deferred in CT-2; and `EDPLACE`)
- `phase-4a:127` Saved capture never uploaded: ⌥⌘U beeps. ⌘U uploads it for the… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-4a:145` Slow profile, "Upload and copy URL": capture something large… (also `EDITOR`, in part since CT-2; and `EDPLACE`, `EDSAVEAS`)
- `phase-4a:146` With an editor open, press Delete on its row and leave the… (also `EDITOR`, in part since CT-2; and `EDPLACE`)
- `phase-7c:175` The background cannot be drawn: with a capture over 16,384 px…; the Save As leg also needs EDSAVEAS; the coordinator's notice is behind EDITOR

### 25. Selection overlay internals (`SELINT`): 4 lines, 3 alone

- Replaces: Inside `SelectionController` (TidyShot/Selection/SelectionController.swift): `NSScreen.screens` (:39, :51, :73), `SelectionWindow` made per screen in `present`, `NSEvent.mouseLocation` (:103-106), and its `WindowPicker` built from `SCShareableContent`.
- Shape: A screens provider and a `SelectionWindow` factory passed to `SelectionController.init`, and a pickable-window list (a protocol over frame and id) in place of `SCShareableContent`.
- Live: `NSScreen.screens`, `SelectionWindow`, the windows from the content.
- Effort for the seam: L
- Note: Built on `TARGET` for the windows and displays it hands back.

Lines (4):

- `phase-1:22` Click without dragging cancels, on the desktop or on a window…
- `phase-6b:57` Lock on (lock shown): a corner or edge drag keeps the ratio the…
- `phase-6b:62` A stored area on a connected display: ⌃⇧1 opens with it… (also `CAPSRC`); placePreselected is SelectionController's own (SELINT)
- `phase-6b:65` Two displays: the rect and the toolbar stay on the display the…

### 26. Editor close sheet (`CLOSESHEET`): 4 lines, 1 alone

- Replaces: `NSAlert.beginSheetModal` in `EditorWindowController.askToSaveBeforeClosing()` (TidyShot/Editor/Window/EditorWindowController.swift:460-481, the sheet at :481).
- Shape: A closure passed to `EditorWindowController.init`: `askToSave(message, informativeText, firstButton) async -> choice`.
- Live: The `NSAlert` sheet as it is.
- Effort for the seam: S

Lines (4):

- `phase-4a:148` Editor open on a capture in the save folder: Settings >… (also `EDITOR`, in part since CT-2; and `EDPLACE`, `EDSAVEAS`)
- `phase-4a:152` With changes, ⌘W (or the close button) shows a sheet: Do you…
- `phase-4a:153` On an upload-only capture that finished uploading, the first… (also `EDSAVEAS`)
- `phase-4a:155` Quit TidyShot from the menu with a changed editor: the sheet… (also `EDITOR`, in part since CT-2; and `APPDELEGATE`)

### 27. URL command log closure (`URLLOG`): 4 lines, 2 alone

- Replaces: `URLCommandHandler`'s direct `NSLog` calls (TidyShot/URLScheme/URLCommandHandler.swift:86, :155, :178, :210); the coordinator builds the handler privately (AppCoordinator.swift:36-40).
- Shape: A `log` closure on `URLCommandHandler.init`, fed from `environment.log`.
- Live: `NSLog("%@", ...)`.
- Effort for the seam: S

Lines (4):

- `phase-6b:152` t 'capture-area?action=%25@%25n%25s': Unknown action “%@%n%s”…
- `recording-r3:419` 9. The prompts' order and log lines are as the Camera prompt… (also `LOG`, in part since CT-3)
- `recording-r4:187` record-screen during a recording is dropped, logged URL command…
- `recording-r4:192` Two record-screen URLs back to back (one Keyboard Maestro… (also `LOG`); one start and no notice are A now

### 28. Recording chrome's not-filmed mapping (`CHROMEMAP`): 3 lines, 3 alone

- Replaces: `RecordingScreenChrome.setFilmed(_:)`'s `notAvailable` (TidyShot/Recording/RecordingChrome.swift:145-156) acts on the private model, which only `show()` fills, and `show()` orders real panels front.
- Shape: A pure static on `BarToggle` (or a test-supplied model on the chrome).
- Live: `setFilmed` calls the static.
- Effort for the seam: S

Lines (3):

- `recording-r3:336` A lookup miss (Not available for this recording, Recorded…
- `recording-r3:413` 4. The filmed features are bubble and highlights, and a missing…
- `recording-r3:432` A. A bar-disabled bubble button keeps its own tool tip when its…

### 29. Save folder chooser (`FOLDER`): 3 lines, 1 alone

- Replaces: `SaveLocation.chooseFolder()` (TidyShot/Output/SaveLocation.swift:31-32, an `NSOpenPanel`), reached through `ensureFolder()` (:64) from `writeFile` and `saveRecording` when no folder is stored.
- Shape: A closure on `SaveLocation` (or `AppEnvironment`): `chooseFolder: () async -> URL?`.
- Live: The `NSOpenPanel` body as it is.
- Effort for the seam: S

Lines (3):

- `phase-1:39` Cancelling the folder chooser leaves the image on the clipboard… (also `TARGET`)
- `recording-r1:303` A card for a temporary file with .none shows Kept in TidyShot… (also `WORKSPACE`)
- `recording-r1:322` No save folder set, Save and copy image: the folder panel opens…

### 30. Capture Text's copy step reachable (`COPYTEXT`): 2 lines, 2 alone

- Replaces: `private func copyText(in:)` (TidyShot/App/AppCoordinator+Capture.swift:270), reached only through `captureText()`/`captureText(at:)`, which need `CAPSRC`; `TextRecognizer()` (:273).
- Shape: A method made internal (an access change), optionally with a `recognizeText` closure on `AppEnvironment`.
- Live: `TextRecognizer().recognize`.
- Effort for the seam: S

Lines (2):

- `phase-7b:77` An empty area (the grey box, or a plain part of the desktop)…
- `phase-7b:78` Show notification off, Play sound off: a paragraph is copied…; FakeNotifier keeping openURL

### 31. Quit reply decision (`APPDELEGATE`): 2 lines, 1 alone

- Replaces: `AppDelegate.applicationShouldTerminate` (TidyShot/App/AppDelegate.swift:69-84) returns `.terminateNow` under tests (:70) and reads `AppCoordinator.shared` (:72).
- Shape: The reply decision moved into a method that takes the coordinator (or the coordinator injected into the delegate).
- Live: `applicationShouldTerminate` calls it with `AppCoordinator.shared`.
- Effort for the seam: S

Lines (2):

- `phase-4a:155` Quit TidyShot from the menu with a changed editor: the sheet… (also `EDITOR`, in part since CT-2; and `CLOSESHEET`)
- `recording-r1:254` A second quit during a held quit does nothing (no second reply).

### 32. Editor defaults store (`EDDEFAULTS`): 2 lines, 1 alone

- Replaces: `storeChangedDefaults` writes `AppSettings.shared` (TidyShot/Editor/Window/EditorToolbar.swift:165).
- Shape: The coordinator's `AppSettings` passed into `EditorWindowController`.
- Live: `AppSettings.shared`, as the coordinator's settings are in the app.
- Effort for the seam: S

Lines (2):

- `phase-4a:67` Choose blue and 8 pt, close the editor and open another…
- `phase-4c:201` Shape and Size survive a relaunch. Choose Ellipse and Large… (also `EDITOR`)

### 33. Trim poster reader (`POSTER`): 2 lines, 0 alone

- Replaces: `posterFrame(of:scope:)` in `finishTrimWrite` (TidyShot/App/AppCoordinator+Trim.swift:318, :346), over `PosterFrame.image`.
- Shape: A closure on `AppEnvironment`: `posterFrame: (URL, URL?) async -> CGImage?`.
- Live: The static as it is.
- Effort for the seam: S
- Note: Reached only through `TRIM`.

Lines (2):

- `recording-r2:444` When the trimmed file's first frame cannot be read, the card… (also `TRIM`)
- `recording-r2:663` J. The card shows the row's placeholder when the trimmed file's… (also `TRIM`)

### 34. Preferred camera as a pure rule (`CAMPREF`): 1 lines, 1 alone

- Replaces: `LiveCameraDevices.preferred()` (TidyShot/Recording/Bubble/CameraDevices.swift:44-49) reads `AVCaptureDevice.systemPreferredCamera` and the discovery session.
- Shape: A pure static taking the system camera's id and type and the listed cameras, as `CameraChoice` is pure.
- Live: `preferred()` calls it with the AVFoundation values.
- Effort for the seam: S

Lines (1):

- `recording-r3:422` 12. System Default is the system's preferred camera when it is…

### 35. Camera session device behind a protocol (`CAMSESSION`): 1 lines, 1 alone

- Replaces: `CameraSession`'s `AVCaptureSession` and `AVCaptureDevice(uniqueID:)` lookup (TidyShot/Recording/Bubble/CameraSession.swift:56, :77, :129-160; `couldNotStart` :211).
- Shape: A protocol over the session and the device lookup, injected into `CameraSession`.
- Live: `AVCaptureSession` and `AVCaptureDevice`.
- Effort for the seam: M

Lines (1):

- `recording-r3:438` E. A failed start counts as a loss in the run state, so a later…

### 36. Desktop cover internals (`COVERSINT`): 1 lines, 1 alone

- Replaces: Inside `DesktopCoverController`: `WallpaperSource` is a struct (TidyShot/Desktop/WallpaperSource.swift:6), `NSScreen.screens` (DesktopCoverController.swift:125, :147); and `ScreenCapturePermission.isGranted` in the coordinator's `reportFailure` (AppCoordinator.swift:63).
- Shape: A wallpaper protocol and a screens closure passed to `DesktopCoverController.init`, and a permission closure on `AppEnvironment`.
- Live: `WallpaperSource`, `NSScreen.screens`, `ScreenCapturePermission.isGranted`.
- Effort for the seam: M

Lines (1):

- `phase-7b:128` The notification itself (Desktop icons still showing with…

### 37. Template migration log (`MIGLOG`): 1 lines, 1 alone

- Replaces: `NSLog` in `TemplateMigration.removingAppToken` (TidyShot/Output/TemplateMigration.swift:38).
- Shape: A log closure (or sink) passed through `AppSettings(defaults:)`.
- Live: `NSLog`.
- Effort for the seam: S

Lines (1):

- `phase-3-1:59` Again with the Phase 3 build, set the file name template to…

### 38. Canvas modifier flags (`MODIFIERS`): 1 lines, 1 alone

- Replaces: `NSApp.currentEvent?.modifierFlags` in `CanvasView.textView(_:doCommandBy:)` (TidyShot/Editor/Window/CanvasView.swift:984, the read at :987).
- Shape: An injectable `currentModifierFlags: () -> NSEvent.ModifierFlags` on `CanvasView`.
- Live: `NSApp.currentEvent?.modifierFlags ?? []`.
- Effort for the seam: S

Lines (1):

- `phase-4b:53` Shift-Return (or ⌥Return) inserts a newline and Return then…

### 39. Pasteboard target (`PASTEBOARD`): 1 lines, 1 alone

- Replaces: `Pasteboard.write` uses `NSPasteboard.general` (TidyShot/Output/Pasteboard.swift:107-112), behind `copy(annotationClip:)` (:89).
- Shape: `Pasteboard`'s writes taking an `NSPasteboard` (a uniquely named one in tests).
- Live: `NSPasteboard.general`.
- Effort for the seam: S

Lines (1):

- `phase-4b:90` Copy and paste in one editor: select an ellipse, ⌘C, ⌘V. A…

### 40. Scrolling session controller internals (`SCROLLCTL`): 1 lines, 1 alone

- Replaces: Inside `ScrollCaptureController.run` (TidyShot/Scrolling/ScrollCaptureController.swift:35-70): `ScrollAreaFrameWindow`, `ScrollFrameSource` (an `SCStream`), `ScrollCapturePanel`, and the `NSScreen` lookups (:38-39). The settings wiring at :61 and :63 is untested.
- Shape: Factories on `ScrollCaptureController.init` for the frame window, the panel and the frame source (`FakeFrameSource` exists), and a screen lookup.
- Live: The concrete windows, `ScrollFrameSource`, `NSScreen`.
- Effort for the seam: L
- Note: Built on `TARGET` (`run` takes an `SCDisplay`).

Lines (1):

- `phase-5:161` Uncheck the checkbox, finish the session, open another: it is…

### 41. Background fill store (`BGFILL`): 1 lines, 0 alone

- Replaces: `BackgroundFillSource.fillImage` reads `CustomBackgroundStore.shared.image()` (TidyShot/Background/BackgroundFillSource.swift:13), the real container.
- Shape: An injectable store directory, or a fill-image closure on `AppEnvironment`.
- Live: `CustomBackgroundStore.shared`.
- Effort for the seam: S

Lines (1):

- `phase-7c:117` A window capture with the setting on and Custom Image, then a… (also `TARGET`)

### 42. Mute ladder steps (`MUTESTEPS`): 1 lines, 0 alone

- Replaces: `steps: .live` in `muteAndSave` (TidyShot/App/AppCoordinator+Recording.swift:666) and `recoverRecordings` (AppCoordinator+Recovery.swift:122).
- Shape: `RecordingMute.Steps` (a struct of closures, RecordingMute.swift:37) as an `AppEnvironment` member.
- Live: `RecordingMute.Steps.live`.
- Effort for the seam: S

Lines (1):

- `recording-r2:320` **(Debug)** kill -9 during a muted recording, then relaunch… (also `TMPDIRS`)

## Lines that need two or more seams at once

97 lines. Grouped by the seams they need.

- `EDITOR` + `EDPLACE` (24): `coordinator-split:43` Annotate the newest card, Save, then…; `phase-4a:37` "Upload and copy URL", a large capture…; `phase-4a:56` The toolbar shows, in order: the tools…; `phase-4a:58` With the canvas focused, V D X B R A…; `phase-4a:88` ⌘1 shows the picture at its natural…; `phase-4a:94` Saved capture: Redact, ⌘S. The same…; `phase-4a:95` Capture uploaded with "Upload and copy…; `phase-4a:96` Capture from before Phase 3: ⌘S…; `phase-4a:99` Lock the saved file (Finder, Get Info…; `phase-4a:123` Capture uploaded with "Upload and copy…; `phase-4a:124` Upload-only capture that finished…; `phase-4a:131` Enter a wrong secret access key in…; `phase-4a:132` Folder change with a bad key: Settings…; `phase-4a:133` The same wrong key, ⌘U on an…; `phase-4a:151` ⌘W on an editor with no changes closes…; `phase-4b:92` ⌘C with nothing selected still copies…; `phase-4b:106` Capture uploaded with "Upload and copy…; `phase-4b:112` Enter a wrong secret access key in…; `phase-4b:113` The row still copies the old URL…; `phase-4c:94` The toolbar shows fourteen tools, in…; `phase-4c:95` With the canvas focused, S (either…; `phase-7c:72` The toolbar in the editor has a…; `phase-7c:169` Copy (⇧⌘C, or ⌘C with nothing selected…; `phase-7c:170` Save (⌘S) on a capture with a local…
- `CAPSRC` + `RECCHROME` (8): `recording-r2:231` Two GIF recordings converting at once…; `recording-r2:236` Stop Making GIF with one conversion…; `recording-r2:238` Quit during a conversion. Start a 60 s…; `recording-r2:390` A GIF save that ends during a second…; `recording-r2:402` The same with an upload that finishes…; `recording-r2:407` Quit during the second recording of the…; `recording-r2:605` 1. Settings are read at the start: the…; `recording-r2:653` E. A post-Stop notice during a later…
- `EDITOR` + `EDPLACE` + `EDSAVEAS` (5): `phase-4a:97` Upload-only capture that finished…; `phase-4a:102` Saved capture: edit, then ⇧⌘S. The save…; `phase-4a:106` ⇧⌘S on a saved capture and save over…; `phase-4a:147` Delete again and confirm: the subtitle…; `phase-4a:162` Quit, set one record's timestamp in…
- `EDITOR` + `EDPLACE` + `BEEP` (3): `phase-4a:107` Edit, ⌘U, and keep drawing before the…; `phase-4a:127` Saved capture never uploaded: ⌥⌘U…; `phase-4a:146` With an editor open, press Delete on…
- `CAPSRC` + `RECCHROME` + `STAGE` (3): `recording-r1:196` Closing the window during the count-in…; `recording-r2:397` The same with the GIF saved during the…; `recording-r2:409` A quick quit, where nothing else holds…
- `CAPSRC` + `SCROLL` (3): `phase-5:78` Drag an area 400 pt wide and 60 pt…; `phase-5:182` Nothing is written or uploaded before…; `phase-6a:211` The rect survives a relaunch. A window…
- `SAVEAS` + `SCREENS` (3): `phase-6a:172` After the upload, on a card that showed…; `phase-6a:176` Use Save As… from the button and from…; `recording-r1:313` Restoring an uploaded upload-only…
- `TMPDIRS` + `LAUNCH` (3): `coordinator-harness:50` 7. pending/ orphans adopted, never…; `coordinator-harness:69` D27. start()'s one task runs…; `recording-r4:326` 18. No upload resumes by itself at…
- `EDITOR` + `EDPLACE` + `TARGET` (2): `phase-4a:119` "Upload and copy URL" with no…; `phase-4a:120` "Upload and copy URL" with "Also copy…
- `CAPSRC` + `STAGE` (2): `phase-6b:77` 3 seconds and 10 seconds in Settings >…; `phase-6b:79` A self-timer area becomes the previous…
- `CAPSRC` + `COVERS` (2): `phase-7b:96` Not covered: Capture Scrolling (⌃⇧5)…; `recording-r1:122` A window recording with Hide desktop…
- `LOG` + `EXTRAS` (2): `recording-r3:416` 7. The recording's clock times the…; `recording-r3:436` D. Recording: camera could not be…
- `LOG` + `URLLOG` (2): `recording-r3:419` 9. The prompts' order and log lines are…; `recording-r4:192` Two record-screen URLs back to back…
- `TRIM` + `POSTER` (2): `recording-r2:444` When the trimmed file's first frame…; `recording-r2:663` J. The card shows the row's placeholder…
- `EDITOR` + `EDPLACE` + `TARGET` + `BGPOP` (1): `phase-7c:187` Open the window capture in the editor…
- `EDITOR` + `EDPLACE` + `EDSAVEAS` + `BEEP` (1): `phase-4a:145` Slow profile, "Upload and copy URL"…
- `EDITOR` + `EDPLACE` + `EDSAVEAS` + `CLOSESHEET` (1): `phase-4a:148` Editor open on a capture in the save…
- `EDITOR` + `EDPLACE` + `BGPOP` (1): `phase-7c:171` Annotate the saved capture again: it…
- `EDITOR` + `TARGET` + `PINS` (1): `phase-6b:118` action=annotate: the after-capture…
- `EDITOR` + `SAVEAS` (1): `phase-6a:198` Upload only, after the upload: the card…
- `EDITOR` + `SAVEAS` + `SCREENS` + `PINS` (1): `coordinator-split:44` Pin, then the pin menu's three items…
- `EDITOR` + `SAVEAS` + `PINS` (1): `phase-6a:199` An edited capture's drag copy is…
- `EDITOR` + `SCREENS` (1): `phase-6a:164` A restored card's Annotate opens the…
- `EDITOR` + `EDSAVEAS` (1): `phase-7c:172` Save As… (⇧⌘S): the file is the…
- `EDITOR` + `QASTACK` (1): `phase-6a:131` Delete a card in the middle of the…
- `EDITOR` + `CLOSESHEET` + `APPDELEGATE` (1): `phase-4a:155` Quit TidyShot from the menu with a…
- `EDITOR` + `EDDEFAULTS` (1): `phase-4c:201` Shape and Size survive a relaunch…
- `TARGET` + `SCREENS` + `WORKSPACE` (1): `coordinator-split:36` Capture Area: the file, the card and…
- `TARGET` + `UPLOADFORM` (1): `phase-2:33` Delete the "TidyShot S3 credentials"…
- `TARGET` + `FOLDER` (1): `phase-1:39` Cancelling the folder chooser leaves…
- `TARGET` + `BGFILL` (1): `phase-7c:117` A window capture with the setting on…
- `CAPSRC` + `RECCHROME` + `EXTRAS` (1): `recording-r1:102` Stop each way, one recording each…
- `CAPSRC` + `RECCHROME` + `EXTRAS` + `STAGE` + `COVERS` (1): `recording-r1:124` The covers are gone after Stop, after…
- `CAPSRC` + `RECCHROME` + `STATUSMENU` (1): `recording-r2:351` With the prompt up: a second Record…
- `CAPSRC` + `TMPDIRS` + `LOG` (1): `recording-r4:217` The record shortcut during the settle…
- `CAPSRC` + `EXTRAS` (1): `recording-r3:276` A failed content read: not forceable by…
- `CAPSRC` + `STAGE` + `STATUSMENU` (1): `phase-6b:75` While the countdown runs, ⌃⇧4, the…
- `CAPSRC` + `STAGE` + `SCROLL` (1): `phase-6b:159` While a selection is open (⌃⇧4, not…
- `CAPSRC` + `SELINT` (1): `phase-6b:62` A stored area on a connected display…
- `CLOP` + `TMPDIRS` (1): `recording-r1:296` Cleanup. ls $C/tmp/Clop is empty after…
- `SAVEAS` + `WORKSPACE` (1): `recording-r2:264` A GIF's card and row. The card has the…
- `SCREENS` + `PINS` (1): `phase-6b:83` Pin a window or fullscreen capture…
- `SCREENS` + `WORKSPACE` (1): `recording-r4:275` A click on the thumbnail opens the link…
- `TMPDIRS` + `MUTESTEPS` (1): `recording-r2:320` **(Debug)** kill -9 during a muted…
- `EDSAVEAS` + `CLOSESHEET` (1): `phase-4a:153` On an upload-only capture that finished…
- `PINS` + `STATUSMENU` (1): `phase-6b:89` Lock: the border goes and clicks pass…
- `WORKSPACE` + `FOLDER` (1): `recording-r1:303` A card for a temporary file with .none…

## Seams that unlock three or fewer lines

- Recording chrome's not-filmed mapping (`CHROMEMAP`, effort S), 3 lines: `recording-r3:336` A lookup miss (Not available for this…; `recording-r3:413` 4. The filmed features are bubble and…; `recording-r3:432` A. A bar-disabled bubble button keeps its own…
- Save folder chooser (`FOLDER`, effort S), 3 lines: `phase-1:39` Cancelling the folder chooser leaves the image… (also `TARGET`); `recording-r1:303` A card for a temporary file with .none shows… (also `WORKSPACE`); `recording-r1:322` No save folder set, Save and copy image: the…
- Capture Text's copy step reachable (`COPYTEXT`, effort S), 2 lines: `phase-7b:77` An empty area (the grey box, or a plain part of…; `phase-7b:78` Show notification off, Play sound off: a…
- Quit reply decision (`APPDELEGATE`, effort S), 2 lines: `phase-4a:155` Quit TidyShot from the menu with a changed… (also `EDITOR`, `CLOSESHEET`); `recording-r1:254` A second quit during a held quit does nothing…
- Editor defaults store (`EDDEFAULTS`, effort S), 2 lines: `phase-4a:67` Choose blue and 8 pt, close the editor and open…; `phase-4c:201` Shape and Size survive a relaunch. Choose… (also `EDITOR`)
- Trim poster reader (`POSTER`, effort S), 2 lines: `recording-r2:444` When the trimmed file's first frame cannot be… (also `TRIM`); `recording-r2:663` J. The card shows the row's placeholder when… (also `TRIM`)
- Preferred camera as a pure rule (`CAMPREF`, effort S), 1 line: `recording-r3:422` 12. System Default is the system's preferred…
- Camera session device behind a protocol (`CAMSESSION`, effort M), 1 line: `recording-r3:438` E. A failed start counts as a loss in the run…
- Desktop cover internals (`COVERSINT`, effort M), 1 line: `phase-7b:128` The notification itself (Desktop icons still…
- Template migration log (`MIGLOG`, effort S), 1 line: `phase-3-1:59` Again with the Phase 3 build, set the file name…
- Canvas modifier flags (`MODIFIERS`, effort S), 1 line: `phase-4b:53` Shift-Return (or ⌥Return) inserts a newline and…
- Pasteboard target (`PASTEBOARD`, effort S), 1 line: `phase-4b:90` Copy and paste in one editor: select an…
- Scrolling session controller internals (`SCROLLCTL`, effort L), 1 line: `phase-5:161` Uncheck the checkbox, finish the session, open…
- Background fill store (`BGFILL`, effort S), 1 line: `phase-7c:117` A window capture with the setting on and Custom… (also `TARGET`)
- Mute ladder steps (`MUTESTEPS`, effort S), 1 line: `recording-r2:320` **(Debug)** kill -9 during a muted recording… (also `TMPDIRS`)

## A lines that name a seam

- `phase-3:46` (Wi-Fi off, upload-only Retry): the evidence names `TARGET` only as the way a fresh capture's first upload would enter. The line is coverable now through `retryUpload` over a pending image; no seam needed.
- `recording-r4:378` (call H, part retry from held bytes): the notes cite harness D18's read counter on `readPart`, then say rewriting part 3's bytes between attempts needs no seam, only a FakeDestination extension (a digest of each part's data). No seam needed.
- `recording-r2:364` (a Record press with access undecided while another capture runs): the first half is A and covered in part in tests-A; the second half, a press once the capture is done, reaches `Recording.makeDirectory` and needs `TMPDIRS`. It is listed under `TMPDIRS` as a second half and not counted in the B totals.
- The 14 lines tests-A moved from A to B are no longer A lines. They are counted here as B: 13 under `EDITOR` and recording-r2:241 under `TMPDIRS`.

One B line has a part that is A: the held-prompt part of `recording-r2:351` (a second Record press does nothing, captures are refused, Quit starts nothing). tests-A tests it in `CoordinatorRecordingTests.aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing`. The line stays B for its other parts and stays under `CAPSRC`, `RECCHROME` and `STATUSMENU`.

## Fake extensions some lines also need

Not seams, but the lines below need them as well as the seam named:

- `phase-4a:49`: the Wi-Fi-off half also needs FakeDestination.download(key:) to throw
- `phase-6a:160`: also a FakeCards that pushes the oldest card out past a limit
- `phase-6a:172`: also FakeDestination.download(key:) able to throw
- `phase-6b:87`: FakeClipboard keeping the PNG bytes, for the pixel size
- `phase-7b:78`: FakeNotifier keeping openURL
- `recording-r1:314`: also a FakeCards.show that keeps the poster
- `recording-r2:351`: nothing for its seams; its held-prompt part is A, and its test in tests-A needs a held microphone fake (`HeldMicrophoneDevices`, the `HeldCameraDevices` pattern)
- `recording-r2:625`: also FakeDestination.download(key:to:) able to throw (today a no-op); TRIM for the method part

## How the readers' names map

- `TARGET`: CaptureResult/CaptureTarget seam, SEAM-TARGET, seam 1 (6b), value-type CaptureTarget, Save seam.
- `EDITOR`: S1 editor window factory, editor presenter, editor bridge, seam 8 (6b).
- `CAPSRC`: SEAM-CONTENT, capture engine seam, capture source (seam 2, 6b), engine and selector (7b), and the content and selector half of the recording start seam (r1 S1, r2).
- `RECCHROME` (+ `STAGE`, `EXTRAS`): the rest of the recording start seam (chrome factory, count-in stage and screen geometry).
- `SCREENS`: NSScreen/overlay screen seam, S4 (r1), screen provider for pinScreen.
- `PINS`: PinController behind a protocol (coordinator-split, seam 4 in 6b) and the panel factory the 6b cross-check asked for, merged.
- `SAVEAS`: Save As panel seam (6a), S6 (r1), Save As panel on AppEnvironment (r2, r4). `EDSAVEAS`: S2 (4a), Save As panel in 7c. `CLOSESHEET`: S3 (4a). `EDDEFAULTS`: S4 (4a), editor defaults store (4c).
- `STATUSMENU`: status icon (phase-2), StatusMenuController NSStatusItem (3.1), seam 5 (6b), S2 (r1), status menu builder (r2).
- `TMPDIRS`: S7 (r1), tmp/ directory statics (r2, r3). `LAUNCH`: launchRecovery (coordinator-harness), start() injection (r4), launch backfill (small-tweaks).
- `LOG`: RecordingLog sink/seam/closure (coordinator-harness, r3, r4). `URLLOG`: seam 6 (6b), URLCommandHandler log closure (r4). `MIGLOG`: TemplateMigration log (3.1).
- `SELINT`: SelectionController screens and window list (phase-1), seam 7 (6b). `STAGE`: seam 3 (6b). `COVERS`: S9 (r1), covers seam (7b). `COVERSINT`: WallpaperSource/NSScreen/permission seam (7b).
- The rest keep the reader's own name: Clop (S3 in r1), Trim window, poster reader, mute steps, RecordingExtras factories, CameraSession, preferred camera, chrome setFilmed mapping, AppDelegate quit reply, modifier flags, Pasteboard, background popover, background fill, beep, copyText, SEAM-SCROLL, SEAM-CTL, QuickAccessController stack, UploadSettingsModel, NSWorkspace, folder chooser.
