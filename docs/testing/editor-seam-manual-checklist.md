# Editor seam manual checklist

Run after the editor seam phase (`docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`), and after any
later change to `EditorPresenting`, `AppEnvironment.makeEditor` and its live closure, `presentEditor`,
`editorDidClose` or `reviewEditorsBeforeQuit`. The suite now opens every editor through `world.editors`, a
`FakeEditor` per open, and the coordinator-split, phase-4a, phase-4b, phase-4c, phase-6a, phase-6b, phase-7c and
small-tweaks checklists mark 65 lines `(suite …)`, 25 in full and 40 in part. The live closure never runs in the suite
(`AppEnvironment.live()` builds `AppSettings.shared`, the Keychain store and the notifier), so what is left here is
the real editor window it builds: that it opens, saves, closes and asks at a quit as it did before the seam.

## Checks

- [ ] 1. Annotate from a card and from a Recent Captures row each open the editor at the same size as before. The
  title is the file name for a save-folder capture (with its proxy icon) and `Capture <time>` otherwise. A second
  Annotate on another capture opens a window cascaded 22 pt from the first. Annotate on a capture whose editor is
  open brings that window forward, and no second window opens.
- [ ] 2. Draw, then ⌘S: the save-folder file shows the edit and the unsaved dot clears. ⌘C posts `Image copied`.
  ⌘U closes the editor, the row uploads, and the link is copied.
- [ ] 3. ⌘W on a changed editor shows the close sheet. Cancel keeps the editor open; Don't Save closes it. Annotate
  on the same capture then opens a fresh editor. ⌘W on a clean editor closes it at once.
- [ ] 4. Quit with a changed editor: the sheet appears on it. Cancel keeps TidyShot running; quit again and Don't Save
  quits.

## The design's calls, to confirm or overrule

The design lists them in section 10. Write `confirm` or `overrule` and why; an overrule goes in its built notes.
- [ ] 1. One seam, `EDITOR`; the window's own screen read and workspace observer (`EditorWindowPlacement`) are a
  second seam, deferred as `EDPLACE`. ______
- [ ] 2. The protocol is `EditorPresenting`, class-bound, with four members, after `EditorActions` in
  `EditorWindowController.swift`; the conformance is an empty extension at the end of the file. ______
- [ ] 3. The factory is one `@MainActor` closure, `AppEnvironment.makeEditor`, taking the model, the actions, the
  title, the represented URL and the close callback, so the controller's `onClose` is untouched. ______
- [ ] 4. The registry becomes `[UUID: any EditorPresenting]`; `reviewEditorsBeforeQuit` stays byte for byte. ______
- [ ] 5. No presenter type: the fake's `Push` reads the same pure functions the controller does. ______
- [ ] 6. `FakeEditor` and `FakeEditors` in `Support/EditorFakes.swift`, `world.editors`, `FakeClipboard.pngs` and
  `EditorPixels` are support, not seams. ______
- [ ] 7. A line naming the window's glue (the dot, the subtitle as shown, greying, key routing, closing) is marked in
  part until `EDPLACE`. ______
- [ ] 8. The suites: `CoordinatorEditorTests` for opening, pushes and the quit; the new `CoordinatorEditorSaveTests`
  and `CoordinatorEditorUploadTests` for the actions; one test in `CoordinatorOverlayTests` for phase-6a's delete
  sentences. ______
- [ ] 9. Lines at odds with the code are not reworded; the tests pin the code and each mark says what it pins. Your
  call on the wording: phase-4a's folder change with a bad key (Retry Failed Uploads does nothing for a failed
  replace; the next ⌘U recovers it), "after the retries" in phase-4a's and phase-4b's wrong-key lines (a 403 is not
  retried) and the notice's title `Not uploaded`, phase-6a's "from the card" after an Annotate (the card is closed for
  good, and in upload-only mode ⌘S is Save As…), and phase-7c's flat reopen (only once the first editor has
  closed). ______
- [ ] 10. The `EDPLACE` design is kept beside the design as
  `docs/superpowers/notes/2026-10-30-editor-seam/edplace-design.md`, and seams.md has its row. ______
- [ ] 11. Five of the 13 lines read off a constructed controller are marked in part now, through the pushes and the
  coordinator's copy, with `EDPLACE` named for the rest. ______
- [ ] 12. `BEEP` widens to every beep of the editor window and its `send`; the refusal itself stays the
  validation's (`EDPLACE`). ______
- [ ] 13. Two lines the judge's draft had in full are in part: the window coming forward on a second Annotate (by hand
  for good) and a restored card's Annotate (the restore reads the screens, `SCREENS`). ______

## The plan's decisions, to confirm or overrule

The plan lists them at its end (`docs/superpowers/plans/2026-10-30-editor-seam.md`, Plan decisions). None changes what
a user could see. One gives a number other than the design's:
- [ ] seams.md's table is sorted by Lines, so `TARGET` (34 lines) is third, ahead of `CAPSRC` (33), and the first
  three seams complete 78 lines; the design's section 11 says fourth and 58. Every row's numbers, the three sums and
  the first ten's 152 are the design's. ______

## Observations
Write into the design's built notes: anything above that failed, and each call and decision confirmed or overruled.
