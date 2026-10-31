# Obsolete (E) lines and lines that contradict the code

Checked against the code at e011d2f (main after PR #27, branch checklist-tests, clean) and the newest
designs in docs/superpowers/specs/. "Screenshot design" is
docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md; "recording design" is
2026-10-21-tidyshot-screen-recording-design.md; "R3 design" is 2026-10-24-tidyshot-screen-recording-r3-design.md;
"harness design" is 2026-10-29-tidyshot-coordinator-harness-design.md. Checklist paths are
docs/testing/<file>-manual-checklist.md.

Counts. Part 1: 29 E lines. 22 are confirmed obsolete. 7 are reclassified because the rule still
exists: to D phase-2 52 and phase-3 28, 32 and 67, each with a mark in marks-D.md; to A phase-3 23, 26
and 31, each covered by a test in tests-A.md (phase-3 26 also has a D half, marked in marks-D.md). A line
that duplicates a newer checklist line stays in its checklist, so the checklists stay complete, and takes
the newer line's mark. Part 2: 21 lines that readers flagged as
contradicting the code. All 21 are confirmed, and each gets a corrected text. Part 3: 4 flagged
lines that are not contradictions (phase-4b 112, phase-5 162, recording-r4 377 and 378).

Rule used in Part 1: a line stays E when what it checks no longer happens on any surface, or now
happens differently. When the same behaviour still happens through the surface that replaced the
old one, the rule exists. The line is then reclassified by that rule, and where a newer checklist
line already checks it, the note says the old line is a duplicate.

## Part 1. E lines

### phase-2

- Line 22, "Random name length stepper stops at 4 and 32; the example key updates as the prefix
  and length change." **E confirmed.** The stepper and the prefix field are gone. The key template
  replaced them (screenshot design 2.4, Object key templates, line 84; S3DestinationConfig.swift:20-22).
  Settings > Upload has a `Key template` field and an `Example:` caption (UploadSettingsView.swift:60, :70).
  The random length is now `{random:N}`, clamped to 1...64 (TemplateExpander.swift:68,
  TemplateExpanderTests.randomLengthDefaultsAndClamps). The 4...32 clamp survives only in the
  Phase 2 migration (ObjectKeyNamer.swift:103-112, ObjectKeyNamerTests.migratedTemplateFromPhase2Settings).
- Line 34, "Set key prefix `shots` ...". **E confirmed.** Same replacement: the template
  `shots/{random:6}` does this now. The prefix-to-template migration is in
  S3DestinationConfig.init(from:) (S3DestinationConfig.swift:51-70) and is pinned by
  S3DestinationConfigTests.phase2PrefixAndLengthMigrateToTemplate. The URL with the folder is
  pinned by S3DestinationConfigTests.publicURLFromTemplate.
- Line 45, "A second capture replaces the panel with the new capture." **E confirmed for the
  default settings.** Phase 6a stacks cards newest first (screenshot design 2.9, 6a Stacking,
  line 735; QuickAccessController.show inserts at index 0, QuickAccessController.swift:138, then
  trims to `overlayMaxCards`, :258-262). The default is 5 (AppSettings.swift:279). The old behaviour
  is kept only with `Show up to 1 overlay`: the design says that with 1 card the behaviour equals
  Phase 5's, and the older card closes as `.pushedOut`. Rewritten line if wanted: "With Overlay >
  `Show up to 1 overlay`, a second capture replaces the card." That line would be C, or B with the
  stack seam that phase-6a lines 127-132 name.
- Line 52, "Recent Captures titles contain only words, times and file names, no emoji."
  **Reclassify to D.** The text submenu became custom rows in Phase 3.1 (screenshot design 2.5,
  line 90), but the rule still holds. A row's text is RecentCaptureFormatting.name (the object or
  file name, RecentCaptureFormatting.swift:8-10) and detail (the relative time, the size, and a
  state word such as `Uploading`, `Upload failed` or `Optimizing…`, :19-25 and :39-59). It has no
  emoji. The exact strings are pinned by RecentCaptureFormattingTests.nameIsTheObjectOrTheFileName,
  detailIsTheTimeAndTheSize and detailIsTheTimeTheSizeAndEachUploadState. Corrected text:
  "Recent Captures rows show only the object or file name, the relative time, the size and the
  upload state in words, no emoji." The mark is in marks-D.md.

### phase-3-1

- Line 16, "Items in order: Capture Area `⌃⇧4`, Capture Window `⌃⇧2`, Capture Fullscreen `⌃⇧3`,
  Recent Captures ...". **E confirmed.** Phases 6a, 6b, 7b, R1 and R2 added items.
  StatusMenuController.rebuild (StatusMenuController.swift:75-136) now builds the menu below,
  idle and with the permission granted. Sources: All-in-One, Previous Area and Self-Timer in
  screenshot design 2.9; Capture Text and Hide Desktop Icons in 2.10; Record Screen and Record
  Fullscreen in recording design line 69-70; the GIF items in R2 design line 161.
  If the line is rewritten for the current build: "Items in order: `All-in-One  ⌃⇧1`,
  `Capture Area  ⌃⇧4`, `Capture Window  ⌃⇧2`, `Capture Fullscreen  ⌃⇧3`, `Capture Scrolling  ⌃⇧5`,
  `Capture Previous Area  ⌃⇧6`, `Self-Timer`, `Capture Text  ⌃⇧7`, `Record Screen  ⌃⇧8`,
  `Record Fullscreen`; a separator; Recent Captures (with a chevron), `Restore Closed Overlay`,
  Retry Failed Uploads (only with a failed upload), Reveal Last Capture, `Hide Desktop Icons`; a
  separator; `Unlock Pinned Screenshots` and `Close Pinned Screenshots` when they apply,
  Settings… `⌘,`, Quit TidyShot `⌘Q`." During a recording, `Stop Recording  ⌃⇧8` and a separator
  come first and the two Record items are hidden (:80-82, :106-109). During a GIF conversion,
  `Making GIF… <n> %` and `Stop Making GIF` come first (:84-90). Without the permission, the first
  item is `Screen Recording permission needed…` (:94-97). The rewritten line would be B, with the
  menu-model seam that this file's line 22 names.

### phase-3 (Gallery section)

The checklist's own header (lines 3-8) says to skip this section. No gallery code remains:
`grep -ri gallery TidyShot TidyShotTests` finds nothing. Screenshot design 2.5 (line 90) replaced
the window with the Recent Captures hover submenu, and line 92 replaced the three-button alert
with Delete/Cancel plus a second Remove/Cancel alert.

- Line 20, "The menu shows "Recent Captures…" and no submenu; ...". **E confirmed.** Recent
  Captures is now a submenu. With an empty history it shows a greyed `No captures yet`
  (RecentCapturesMenu.swift:45; phase-3-1 line 37).
- Line 21, the grid with thumbnails and status capsules. **E confirmed.** The grid and capsules
  are gone. What survives is already checked elsewhere: a Phase 2 capture gets its thumbnail on
  first display (phase-3-1 line 27), and a missing file is not tried again
  (ThumbnailProviderTests).
- Line 22, hover highlight and right-hand pane. **E confirmed.** The floating preview panel
  replaced the pane (screenshot design 2.5; PreviewPanel; phase-3-1 lines 40-43).
- Line 23, "Clicking an Uploaded cell copies the URL ...; clicking a Saved cell copies the file
  ...". **Reclassify to A (S).** The rule is unchanged on the submenu row: the row click calls
  AppCoordinator.copyLinkOrFile (AppCoordinator+RecordActions.swift:9-20), which copies `linkURL`
  or, with no link, the file. No existing test calls copyLinkOrFile; tests-A's new
  CoordinatorRecordActionsTests.copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile does, and covers
  this line in part, with phase-2 line 51 and phase-3-1 line 30 (the catalogue's C for line 30 is
  moved to A by the same ruling). This line duplicates phase-3-1 line 30. It stays in the phase-3
  checklist, is not rewritten, and takes line 30's mark; the menu closing stays by hand.
- Line 24, the context menu with Copy URL or Copy File, Retry Upload, Reveal in Finder and
  Delete…. **E confirmed.** The row has link, photo and trash buttons instead
  (RecentCaptureRow.swift). Retry moved to Retry Failed Uploads and to the card's Retry.
- Line 25, the one alert with "Delete", "Remove from History Only" and "Cancel". **E confirmed.**
  That alert was withdrawn (screenshot design 2.5, Simpler delete confirmation, line 92). The
  first alert is now `Delete this capture?` with one line and Delete/Cancel
  (CaptureDeletion.swift:8, :114-119; AppEnvironment.swift:87 confirmDelete). The second alert is
  Remove/Cancel (AppEnvironment.swift:106 confirmRemoveFromHistory). It is pinned by
  CaptureDeletionTests.confirmationTextIsOneLine. The newer check is phase-3-1 line 46.
- Line 26, Delete… on a Phase 2 capture that was uploaded: the alert says the object stays, and
  Delete removes the row and the file. **Reclassify: D for the alert text, A (S) for the
  coordinator part.** The text `... The uploaded object stays in the bucket.`
  (CaptureDeletion.swift:117-119) is pinned by
  CaptureDeletionTests.confirmationTextSaysWhenTheObjectStays. A pre-Phase 3 record has no
  `objectLocation`, so CaptureDeletion.objects(for:) (CaptureDeletion.swift:55-58) sends no
  DELETE. No existing coordinator test checks that; tests-A's new
  CoordinatorDeleteTests.aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest does. The D half's
  mark is in marks-D.md, and the line's one mark names both tests. Its alert text duplicates
  phase-3-1 line 48; the line stays in its checklist.
- Line 27, Delete… while offline: notification "Not deleted" and the row stays. **E confirmed
  (changed).** A failed DELETE now opens the second alert, `Couldn't delete it from storage: <reason>`
  with `Remove it from history anyway? The object stays in the bucket.` and Remove/Cancel
  (AppCoordinator+Delete.swift:62-67; CaptureDeletion.swift:11, :126). The newer check is
  phase-3-1 line 49.
- Line 28, a second Delete… while the request hangs opens no second alert. **Reclassify to D.**
  The rule is unchanged: the `deletingIDs` guard at AppCoordinator+Delete.swift:16. It is pinned
  by CoordinatorDeleteTests.deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing. That test holds
  the second Delete at the first alert, not during the storage request, but the guard is one: it is
  set at :22 and cleared in the defer at :27-30, so it holds through the request too. This line
  duplicates phase-3-1 line 55, which is D for the same reason (the catalogue had it as A, and
  tests-A.md withdrew its new test for it). Both stay in their checklists with the same mark, in
  marks-D.md.
- Line 29, Forget Credentials, then Delete…: "Not deleted" notification and "Remove from History
  Only". **E confirmed (changed).** With no credentials the second alert reads
  `Couldn't delete it from storage: No credentials are saved in Settings > Upload.`
  (AppCoordinator+Delete.swift:120-122). Remove from History Only is gone. The newer check is
  phase-3-1 line 52. The reason is pinned for aborts by
  CoordinatorDeleteTests.noStoredCredentialsIsTheAbortsReason.
- Line 30, an undeletable local file (`chflags uchg`): "Not deleted" notification. **E confirmed
  (changed).** When a save-folder file cannot be removed, the second alert now reads
  `Couldn't delete the file: <reason>` with `Remove it from history anyway? The file stays where it is.`
  (AppCoordinator+Delete.swift:75-89; CaptureDeletion.swift:15, :132). `Not deleted` is posted
  only for a `pending/` file (AppCoordinator+Delete.swift:73), which is pinned by
  CoordinatorDeleteTests.aPendingFileThatCannotBeRemovedKeepsTheRecord. Rewritten line if
  wanted: "Make the local file of a Saved capture undeletable (`chflags uchg <file>`), Delete:
  the second alert `Couldn't delete the file: …` with Remove and Cancel; Cancel keeps the row;
  `chflags nouchg <file>`, Delete works." That line would be A (S), using a save-location fake
  whose remove throws. phase-3-1 line 53 checks the same alert for a moved save folder.
- Line 31, after a bucket change, Delete… removes the object from the bucket it was uploaded to.
  **Reclassify to A (S).** The rule is unchanged. deleteCapture deletes each group at the
  location stored on the record (AppCoordinator+Delete.swift:54-62), and deleteObjects builds the
  destination from `location.config`, not from the current settings (:111-123). The pure part is
  pinned by CaptureDeletionTests.objectsIncludeSupersededAtTheirLocations. No newer checklist
  line checks this. tests-A's new CoordinatorDeleteTests.aDeleteAfterABucketChangeDeletesWhereTheObjectWent
  covers the coordinator part. Corrected text: "Change the Upload tab's bucket and Save, then Delete a
  capture uploaded before the change (trash button on its row or card): the object is removed
  from the bucket it was uploaded to (`curl -I <old url>` gives 403 or 404), not looked for in
  the new one."
- Line 32, two captures under `shared/{date}` share a key; Delete the first: "Not deleted from
  storage", the row goes, and the second URL still works. **Reclassify to D** for the delete
  side. The text and behaviour are unchanged (AppCoordinator+Delete.swift:53-61, :99-104), pinned
  by CoordinatorDeleteTests.aSharedKeyKeepsTheObjectAndSaysSo. The premise that HEAD answering
  403 counts as a free key is S3Destination.exists (S3Destination.swift:33-35). Only the real
  bucket's 403 is left as a hand detail, so its mark in marks-D.md is in part. Corrected text: the
  same line, with "Delete… the first" changed to "Delete the first from its row".
- Line 33, Retry Upload on a Failed capture. **E confirmed.** The per-item Retry Upload is gone.
  Retry Failed Uploads (AppCoordinator+Upload.swift:496-506) and the card's Retry replaced it.
  Both are checked elsewhere (phase-3-1 line 22, phase-2 line 48) and pinned by
  CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem.
- Line 34, the window remembers its size and position; Escape and ⌘W close it. **E confirmed.**
  There is no window.
- Line 35, with the window open a new capture appears at the top. **E confirmed.** There is no
  window. The submenu is rebuilt each time it opens (StatusMenuController.swift:111-112).

### phase-3 (History hygiene)

- Line 67, "Quit, replace `history.json` with `not json`, relaunch: Recent Captures shows "No
  captures yet", `thumbnails/` and `pending/` are untouched, and `history.json.corrupt-<number>`
  exists." **Reclassify to D, with the text corrected.** The rule still exists: the corrupt file
  is set aside and not overwritten (HistoryStore.swift:51, :185), and nothing is deleted after an
  empty load. Since harness design 4.2 (lines 162-175), start() lists `pending/` after
  `history.load()` (AppCoordinator.swift:302-305) and adopts every file no record names
  (AppCoordinator+Recovery.swift:13-44). After a corrupt history, every readable file in
  `pending/` comes back as a recovered row, with a `Recovered a capture` or `Recovered a recording`
  notice. An empty or unreadable file is removed and logged (AppCoordinator+Recovery.swift:24-27).
  So "No captures yet" holds only when `pending/` is empty, and "`pending/` untouched" fails for an
  empty or unreadable file. This is pinned by HistoryStoreTests.corruptFileIsSetAsideNotOverwritten,
  HistoryStoreTests.corruptFileSetAsideSurvivesNameCollision and
  CoordinatorRecoveryTests.anEmptyHistoryAdoptsEveryOrphanAndDeletesNothing; its mark in marks-D.md
  is in part. Corrected text:
  "Quit, replace `history.json` with `not json`, relaunch: `history.json.corrupt-<number>` exists
  and `thumbnails/` is untouched. With `pending/` empty, Recent Captures shows "No captures yet".
  With files in `pending/`, each readable one comes back as a row with a `Recovered a capture`
  (or `Recovered a recording`) notification, and only an empty or unreadable file is removed."

### phase-4a

- Line 35, "The overlay's right column shows Annotate ... above Close and Delete. The overlay is
  the same size as before." **E confirmed.** In 6a, Close moved to a hover badge at the top-left
  (screenshot design 2.9, Card layout, line 739; QuickAccessView.swift:62, :72-85), and 6b added
  Pin between Annotate and Delete (QuickAccessView.swift:27-51). The size is still 340 x 104
  (QuickAccessView.swift:10). The surviving look check is phase-6a line 145, corrected in Part 2.

### phase-4b

- Line 27, "The toolbar shows twelve tools ...". **E confirmed.** Phase 4c made it fourteen tools,
  with Spotlight after Blur and Counter after Text (screenshot design 2.12, Toolbar, line 1330;
  EditorTool.swift:80-83). Phase 7c added a Background button after Options (screenshot design
  2.11, Editor, line 1184; EditorToolbar.swift:31-33, :92). Rewritten line: "The toolbar shows
  fourteen tools, in order: Select, Redact, Pixelate, Blur, Spotlight, Rectangle, Arrow, Ellipse,
  Line, Pencil, Highlighter, Text, Counter and Crop, then the colour button, the options button,
  the Background button, the zoom pop-up, Copy, Save and Upload. Each tool's tooltip names its
  letter: `Select (V)`, `Redact (D)`, `Pixelate (X)`, `Blur (B)`, `Spotlight (S)`, `Rectangle (R)`,
  `Arrow (A)`, `Ellipse (E)`, `Line (L)`, `Pencil (P)`, `Highlighter (H)`, `Text (T)`,
  `Counter (N)`, `Crop (C)`." That line would be D: EditorToolTests.fourteenToolsInToolbarOrder,
  EditorToolTests.everyToolHasSymbolAndTooltipWithLetter and
  EditorToolbarTests.everyToolSegmentHasItsToolTip.

### phase-7-clop

- Line 20, the `Images` section with `Optimize images with Clop`. **E confirmed (strings
  changed).** The recording design (lines 338-339) renamed the section and its strings
  (GeneralSettingsView.swift:54-63). Rewritten line: "Settings > General has an `Optimization`
  section between its first section and `URL commands`: the toggle `Optimize images and videos
  with Clop` (off by default) and the caption `Clop greatly reduces file size. It keeps its own
  copy of each image and video it optimizes, so long recordings also take space in Clop's cache.`
  With Clop installed there is no `Get Clop` link." That line would be C.

### phase-7b

- Line 64, the `Hide desktop icons while capturing` caption, then the Self-timer picker. **E
  confirmed (changed).** The caption is the R1 text (recording design line 342;
  CaptureSettingsView.swift:64). Phase 7c's `Add background to window captures` and
  `Edit Background…` now sit between it and the picker (:67-72). Rewritten line: "Settings >
  Capture lists, after `Include window shadow` and its caption, `Hide desktop icons while
  capturing` (off) with the caption `Covers desktop icons and widgets with the desktop picture
  during area, window, fullscreen, previous-area, All-in-One and self-timer captures, and area and
  fullscreen recordings. While covered, the desktop does not take clicks.`, then `Add background
  to window captures`, `Edit Background…` and the `Self-timer` picker." That line would be C. The
  default is pinned by AppSettingsTests.desktopIconSettingsDefaultOffAndPersist.
- Line 66, the menu ending in `Capture Text  ⌃⇧7`. **E confirmed.** R1 added Record Screen and
  Record Fullscreen after Capture Text (recording design lines 69-70; StatusMenuController.swift:106-109).
  R1 and R2 also added Stop Recording and the GIF items (:80-91). The current order is in
  phase-3-1 line 16 above. Its two rules still hold: capture items are disabled while
  `capturesRefused` (:150, ShortcutsTests.aCaptureIsRefusedWhileAnotherRunsOrAPromptIsOpen), and
  `Hide Desktop Icons` is always enabled, with its state from `desktopIconsHidden` (:123-126).
  Rewrite with the current list plus those two rules. The rewritten line would be B (menu-model
  seam).

### recording-r2

- Line 193, the GIF bar "is 208 x 44 pt". **E confirmed (changed).** In R3 an area or fullscreen
  recording carries the highlights and bubble buttons, so the bar is `172 + 36 × slots`: 280 x 44
  for an area GIF (R3 design line 156 and gap 16 at line 245; RecordingController.swift:201-203,
  where `showsOverlayButtons` is `request.extras != nil`; AppCoordinator+Recording.swift:438-439
  returns nil extras only for a window). This is pinned by
  RecordingPanelLayoutTests.areaAndFullscreenBarsAre244And280PointsWide. The section records with
  ⌃⇧8 and an area drag, so the corrected text reads "The bar is 280 x 44 pt with a `GIF` tag
  before the time, no mute button, the highlights and bubble buttons, then Stop and Cancel." The
  rest of the line is unchanged. 208 x 44 is now only a window GIF's bar.
- Line 286, the MP4 bar with sound "is 208 x 44 pt", and 172 x 44 without. **E confirmed
  (changed).** Same R3 rule: an area or fullscreen MP4 is 280 x 44 with sound and 244 x 44
  without. A window recording keeps 208 and 172 (RecordingPanelLayoutTests.theBarsAre172And208PointsWide).
  Corrected text: replace 208 with 280 and 172 with 244 for the area recording the section
  makes, and add "(a window recording: 208 and 172)".

## Part 2. Lines flagged as contradicting the code

### coordinator-split line 42 (Retry Failed Uploads with no destination)

What the code does: when After capture is `Upload and copy URL` and no credentials are stored,
makeDestination() returns nil. persist then sets the state to `.none`, not to a failure
(AppCoordinator+Save.swift:161-169). The warning is
`Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard.`
(:155-158), posted once per launch through warnUploadNotConfiguredOnce (AppCoordinator+Upload.swift:26-30).
The cards show `Saved`. history.failedRecords stays empty (HistoryStore.swift:127-129), so
`Retry Failed Uploads` never appears (StatusMenuController.swift:117-119). Only
`Upload only, keep no local file` gives `.failed(notConfigured)` (:164-166). The line fails as
written.

Corrected text: "Retry Failed Uploads with no destination: one notification [`+Upload`].
Settings > Upload > `Forget Credentials`; After capture `Upload only, keep no local file`. Capture
twice: one `Upload not configured` notification in all (`Set up a destination in Settings >
Upload, then retry from Recent Captures. The image is on the clipboard.`), not one per capture;
both cards say `Upload failed`; the menu gains `Retry Failed Uploads`. Choose it: one `Upload not
configured` notification, `Set up a destination in Settings > Upload, then retry.`, not one per
record. Enter the credentials in Settings > Upload and Save, then choose `Retry Failed Uploads`
again: both rows upload and the menu item goes." The category stays B.

### coordinator-harness line 57 (call 12, "The 33 interpolating NSLog lines outside the coordinator stay")

What the code does: on e011d2f, 20 `NSLog` calls outside AppCoordinator*.swift interpolate into
the format string, and the coordinator has none. They are in BackgroundOptionsView:193,
AppSettings:417, 431, 441 and 455, SettingsOpener:34, DragFileStore:171, SaveLocation:49,
Notifier:22 and 129, HistoryStore:51, 194 and 215, OverlayWindowLookup:21, EditorWindowController:156
and 310, EditorFlattener:103, ConnectionTester:92, TemplateMigration:38 and CanvasView:555. At the
merge base 6a52a7c there were 21 outside (MultipartStore:113 was converted in this phase) and 36
inside the coordinator, so no count on either side is 33. Harness design 5.5 (line 209) also says
a `%` in the text is "harmless at worst (a garbled log line)". That understates the risk: an
interpolated `%@` or `%s` makes NSLog read a vararg that was never passed, which is undefined
behaviour and can crash. HistoryStore:51 interpolates `\(error)`, and Notifier:22 and 129
interpolate system error text.

Corrected text: "12. The 20 interpolating `NSLog` lines outside the coordinator stay (5.5). A `%`
in an interpolated error text is undefined behaviour in NSLog's format, so a crash is possible,
not only a garbled line. ______" Harness design lines 209 and 243 need the same count and wording.
The category stays C, since this is a ruling.

### phase-2 line 32 ("Save and copy image" ... Recent Captures shows the item as `Saved`)

What the code does: a plain save's row shows the time and the size only. The state part is nil
for `.none` (RecentCaptureFormatting.swift:53-59), so no row says `Saved`. The phase-3-1 header
(line 12) already says this. Corrected text: "After-capture action "Save and copy image": no
upload happens, paste gives the image, and the Recent Captures row shows the time and size with
no upload state." The category stays B. Its siblings phase-2 lines 47 and 53 say `Failed`; the
row now says `· Upload failed`.

### phase-2 line 42 (auto-close, "moving away closes it a second later")

What the code does: when the card settles, the countdown starts and runs for
`overlayAutoCloseSeconds` (default 5, AppSettings.swift:277). If the pointer is over the card when
the countdown runs out, the whole countdown starts again (QuickAccessController.swift:353-374;
screenshot design 2.9, Stacking, line 735). There is no close a second after the pointer leaves.
The card closes at the end of the first countdown that finds the pointer elsewhere, which can be
up to 5 s after the pointer leaves. Corrected text: "Auto-close happens 5 s after the upload
finishes; with the pointer over the card when the time runs out, the 5 s start again; after the
pointer leaves, the card closes when the current 5 s run out." The category stays C.

### phase-2 line 51 (a `Saved` item reveals the file)

What the code does: since Phase 3.1 the row click calls copyLinkOrFile
(AppCoordinator+RecordActions.swift:9-20). It copies the link, or the file when there is no link.
It does not reveal. Reveal is the card's thumbnail click and the card's `Reveal in Finder`.
Corrected text: "Clicking an uploaded Recent Captures row copies its URL; clicking a row that was
never uploaded copies the file (paste in Finder makes a copy)." This duplicates phase-3-1 line 30,
which the catalogue has as C and which is A now. The category stays A (S). One test,
tests-A's copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile, covers this line, phase-3 line 23 and
phase-3-1 line 30; only phase-3-1 line 30's menu closing stays by hand.

### phase-4a line 56 (toolbar tools Select ... Arrow)

What the code does: the toolbar is fourteen tools, then colour, options, Background, zoom, Copy,
Save and Upload (EditorTool.swift:80-83; EditorToolbar.swift:31-33). The Copy, Save and Upload
tooltips match (EditorToolbar.swift:98-104). Corrected text: "The toolbar shows, in order: the
fourteen tools (Select, Redact, Pixelate, Blur, Spotlight, Rectangle, Arrow, Ellipse, Line,
Pencil, Highlighter, Text, Counter, Crop), the colour button, the options button, the Background
button, the zoom pop-up, Copy, Save (a downward arrow) and a prominent Upload (a cloud with an up
arrow). Copy, Save and Upload are plain buttons with no menus; their tooltips read `Copy the
image (⌘C)`, `Save (⌘S)` and `Upload and copy the link (⌘U)`. Each tool's tooltip names its
letter." The category is B, under `EDITOR` in seams.md, and this corrected text goes with the B
line. Reading the toolbar's items needs a constructed EditorWindowController, whose init reads
`NSScreen.screens[0]` (EditorWindowController.swift:123) and registers an `NSWorkspace` observer
(:103), so tests-A.md moved the line from A to B.

### phase-4b line 28 (narrow window, "every one of the twelve tools")

What the code does: the toolbar has fourteen tools and a Background button. The minimum width is
pinned for 14 tools at 1134 pt (screenshot design 2.12, line 1330;
EditorWindowGeometryTests.toolbarWithEveryToolFitsASmallDisplay). Corrected text: replace "every
one of the twelve tools, the colour and options buttons" with "all fourteen tools, the colour,
options and Background buttons". The category stays C.

### phase-4b line 130 (VoiceOver with a crop; "Crop again ... lists them")

What the code does: CanvasAccessibility.items filters on `document.crop`
(CanvasAccessibility.swift:20-26). Reopening the Crop tool sets `cropDraft` but leaves
`document.crop` applied (CanvasView.swift:262), so while the Crop tool is open, VoiceOver still
lists only the annotations that reach into the applied crop, even though the canvas shows the
whole image. Undoing the crop, or applying a larger crop that reaches them, lists them. This
matches screenshot design line 441 ("VoiceOver lists ... only an annotation that reaches into
[the applied crop]"). Corrected text: "...they stay in the document, and undoing the crop, or
applying a crop that reaches them, lists them; while the Crop tool is open the list still
follows the applied crop. VO-Space on any element while Crop is active does nothing." The
category stays A (S), covered in part: tests-A's
anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag pins VO-Space doing nothing under Crop,
and the existing CanvasAccessibilityTests.cropHidesAnnotationsOutsideIt pins the listing and the
list after undo. No test reads the list while the Crop tool is open, so that stays by hand.

### phase-4c line 123 ("a drag from there resizes it")

What the code does: SelectTool.mouseDown resizes only from a handle of the current selection
(SelectTool.swift:51-55). On an unselected spotlight, a press within 8 pt of the corner is a hit
(HitTester tests handles before bodies) that selects it and starts a move (:56-67). So the first
drag moves it. A drag from the corner resizes only once the spotlight is selected. Screenshot
design 2.12 (line 1300) says nothing about the corner drag. Corrected text: end the line with
"...lands on the corner handle, which every spotlight has, so it selects the spotlight (a drag
from there moves it; once it is selected, a drag from the corner handle resizes it)." The
category stays D.

### phase-6a line 75 (Settings > Shortcuts list)

What the code does: ShortcutsSettingsView.swift:7-17 lists `Capture area:`, `Capture window:`,
`Capture fullscreen:`, `Capture scrolling:`, `All-in-One:`, `Capture previous area:`,
`Self-timer:`, `Capture text:`, `Record screen:`, `Record fullscreen:` and
`Restore closed overlay:`. Corrected text: "Settings > Shortcuts lists `Capture area:`,
`Capture window:`, `Capture fullscreen:`, `Capture scrolling:`, `All-in-One:` (⌃⇧1),
`Capture previous area:` (⌃⇧6), `Self-timer:` (empty), `Capture text:` (⌃⇧7), `Record screen:`
(⌃⇧8), `Record fullscreen:` (empty) and `Restore closed overlay:` (empty)." The rest of the line
is unchanged. The category stays C.

### phase-6a line 76 (menu bar menu list)

What the code does: the current menu is the list given under phase-3-1 line 16 in Part 1. The
disabled rule holds (StatusMenuController.swift:150). Corrected text: that list, followed by "The
capture items, Record items included, are disabled while a capture, a countdown, a scrolling
session or a microphone or camera prompt runs; Restore Closed Overlay and Hide Desktop Icons are
not." The category stays C (B with the menu-model seam).

### phase-6a line 145 (card right column, "no Pin button yet")

What the code does: the right column is Annotate (`pencil.tip.crop.circle`, help `Annotate`),
Pin (`pin`, help `Pin to screen`) and Delete (`trash`, help `Delete this capture` or
`Cancel the upload and delete this capture`) (QuickAccessView.swift:27-51). The close badge is
`xmark.circle.fill`, help `Close` (:72-85). Corrected text: replace "and nothing else; there is no
Pin button yet" with "with Pin (`pin`, help `Pin to screen`) between Annotate and Delete". The
category stays C.

### phase-6a line 148 (card context menu, "no `Pin to Screen` item yet")

What the code does: QuickAccessView.menuItems (QuickAccessView.swift:91-121) shows `Copy URL`
(disabled without a link), `Copy Image` (images), `Copy File` (when canCopyFile, for recordings),
`Save As…`, `Annotate` and `Pin to Screen` (images), `Trim…` and `Upload Trimmed` (MP4s that
offer them), `Reveal in Finder` (with a save-folder file), a separator, `Close`, and `Delete…`
(or `Delete` with Ask before deleting off). Corrected text for an image card: "It lists
`Copy URL` (greyed while uploading and without a link), `Copy Image`, `Save As…`, `Annotate`,
`Pin to Screen`, `Reveal in Finder` (only when the capture has a file in the save folder), a
separator, `Close`, `Delete…`." Drop "There is no `Pin to Screen` item yet." The category stays C.

### phase-6b line 44 (Settings > Shortcuts after the four recorders)

What the code does: after the four, the list is `All-in-One:`, `Capture previous area:`,
`Self-timer:`, `Capture text:`, `Record screen:`, `Record fullscreen:` and
`Restore closed overlay:` (ShortcutsSettingsView.swift:11-17). Corrected text: "Settings >
Shortcuts lists, after the four capture recorders, `All-in-One:` (⌃⇧1), `Capture previous area:`
(⌃⇧6), `Self-timer:` (empty), `Capture text:` (⌃⇧7), `Record screen:` (⌃⇧8), `Record fullscreen:`
(empty) and `Restore closed overlay:` (empty)." The rest of the line is unchanged. The category
stays C.

### phase-6b line 45 (Self-timer picker "after the three toggles")

What the code does: the picker comes after Freeze screen, Show cursor, Include window shadow,
Hide desktop icons while capturing, Add background to window captures and the `Edit Background…`
button (CaptureSettingsView.swift:51-76). Corrected text: "Settings > Capture has a `Self-timer`
picker with `3 seconds`, `5 seconds` (selected) and `10 seconds`, after `Edit Background…`, at the
end of the first section." The category stays C.

### phase-6b line 46 (menu bar menu list)

What the code does: see phase-3-1 line 16. Corrected text: the current list from Part 1, with
"Every capture item is disabled while a capture, a countdown or a scrolling session runs." kept.
The category stays B.

### recording-r1 line 98 (area recording, "a bar of about 172 x 44 pt")

What the code does: an area recording gets the R3 bar, 244 x 44 with no sound or 280 x 44 with
sound (R3 design line 156; RecordingPanelLayout.swift:33-41;
RecordingPanelLayoutTests.areaAndFullscreenBarsAre244And280PointsWide). The menu part still
holds (StatusMenuController.swift:80-82, :106-109). Corrected text: replace "a bar of about 172 x
44 pt beside the area with `0:00`, `Stop` and `Cancel`" with "a bar of about 244 x 44 pt (280
with sound) beside the area with `0:00`, the highlights and bubble buttons, `Stop` and `Cancel`".
The category stays C.

### recording-r1 line 335 (gap 8, "a 172 x 44 pt bar")

What the code does: the same as line 98. 172 x 44 is now a window recording's plain bar, and the
fullscreen bar is 244 or 280. Corrected text: "8. Panel geometry: 172 x 44 pt for a window
recording without sound, 244 x 44 for an area or fullscreen one (R3); the fullscreen panel sits
`ScrollPanelGeometry.gap` above the bottom of the visible frame. Is the bar the right size and
place? ______" The category stays C.

### recording-r2 line 668 (MP4 with defaults, "the 172 x 44 bar")

What the code does: an area or fullscreen MP4 without sound has the 244 x 44 bar. Corrected text:
replace "the 172 x 44 bar with no mute button when system audio is off" with "the 244 x 44 bar
(172 x 44 for a window) with no mute button when system audio is off". The category stays C.

### small-tweaks lines 7 and 8 ("a pin" Delete)

What the code does: a pin has no Delete. PinView's context menu (PinView.swift:112-134) is
Copy Image, Save As…, Annotate, Opacity, Actual Size, Lock and Close. PinCommand
(PinGeometry.swift:109-116) has no delete key. Screenshot design 2.13 (line 1450) says "the
card's, pin's and row's Delete then act at once", which does not match the code. Corrected text,
line 7: "With it on, Delete on a card and on a Recent Captures row each asks first. The card menu
and the row read `Delete…`." Line 8: "Turn it off. Delete from a card and a row each act at once
with no alert. The card menu and the row read `Delete`." Both stay C. Design 2.13 line 1450 needs
"pin's" removed.

## Part 3. Flagged lines that are not contradictions

- phase-4b line 112. The checklist names the notification's text, `Upload failed. The link still
  shows the earlier image.`, which matches EditorUploadPlan.failedReplaceMessage
  (EditorUploadPlan.swift:31). The title is `Not uploaded` (AppCoordinator+Upload.swift:719;
  harness built note D14). The line does not name a title, so it is not wrong. If the title is
  wanted, write "a `Not uploaded` notification says `Upload failed. The link still shows the
  earlier image.`"
- phase-5 line 162. The fallback text exists (ScrollCaptureView.swift:36-40), but only a session
  without an AutoScrollEnvironment shows it, and ScrollCaptureController.swift:51 always passes
  `.live()`. This matches the plan: the fallback is a follow-up commit made only if delivery fails
  (docs/superpowers/plans/2026-10-21-phase-5-scrolling-capture.md:4609; screenshot design line
  691). The line's conditional ("If the fallback is already in the build") does not apply to this
  build. That makes it stale, not wrong. Possible clarification: "In this build the fallback is
  not switched on (ScrollCaptureController passes a live environment), so if no wheel event
  arrives, report it; the fallback text appears only after the follow-up commit."
- recording-r4 lines 377 (call G) and 378 (call H). The reader's finding is that harness built
  note D18 says these need a per-call Abort script or a read counter. FakeDestination.onCall
  already gives the first, and overwriting the file gives the second. That disagreement is with
  a design note, not with the checklist's expectation. The checklist text stands.
