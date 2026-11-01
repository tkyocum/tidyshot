# Capture seams manual checklist

Run after the capture seams phase (`docs/superpowers/specs/2026-11-01-tidyshot-capture-seams-design.md`), and after any
later change to `CaptureTarget.origin`, `CaptureOrigin`, `AppCoordinator.save(_:from:intent:)`, `CaptureDisplay`,
`CaptureWindow`, `ScreenContent`, or `AppEnvironment.captureSource` and `selector` and their live values. The suite now
drives the save path with an origin it builds (`CaptureSamples`) and the content read and the selection through
`world.source` and `world.selector`, and the coordinator-split, phase-1 to phase-7c, recording-r2, recording-r4 and
small-tweaks checklists mark 44 more lines `(suite …)`, 23 in full and 21 in part. The live values never run in the
suite (`AppEnvironment.live()` builds `AppSettings.shared`, the Keychain store and the notifier), so what is left here
is the real capture and the real overlay: that each does what it did before the seams.

## Checks

- [ ] 1. The real capture of each kind. With `Save and copy image`, ⌃⇧3, ⌃⇧4 (drag an area) and ⌃⇧2 (click a window)
  each leave one PNG in the save folder at the right size (`sips -g pixelWidth -g pixelHeight`: the display, the area
  or the window times the display scale), post `Screenshot saved`, put the image on the clipboard and show a card on
  the capture's display. With `Add background to window captures` on, the window capture is composed and the other two
  are not. ⌃⇧6 recaptures the area. `t 'capture-window?action=copy'` and a click on a window: the image only, and
  `Image copied`. A pin of the newest area capture opens over it.
- [ ] 2. The real selection. ⌃⇧1, ⌃⇧4 and ⌃⇧5 open the overlay on every display with the cards left out of the
  picture; Escape captures nothing; a window click in All-in-One captures that window; a scrolling capture starts its
  session; Record Screen's overlay and the recording start as before. With Screen Recording turned off for TidyShot (in
  System Settings, and back on after), a capture shows the permission window.

## The design's calls, to confirm or overrule

The design lists them in section 10. Write `confirm` or `overrule` and why; an overrule goes in its built notes.
- [ ] 1. `CAPSRC` is built in this phase, as the second task, although by its own lines it is not worth its diff (4 full
  and 8 part lines of 34). Overrule to defer it: its tests, fakes, marks and seams.md joins then go, and `TARGET`
  stands alone at 2373 tests in 196 suites. ______
- [ ] 2. `TARGET` is the internal `save(_:from:intent:)` over `CaptureOrigin`, not a value target the engine resolves
  by id, nor a `CaptureResult` carrying the origin. ______
- [ ] 3. C9 (a width change or the lock toggle arming a disarmed rect, in `SelectionViewArmingTests`) is not built;
  phase-6b:105 keeps arming by a width change or the lock toggle by hand. ______
- [ ] 4. `CaptureDisplay` and `CaptureWindow` carry the ScreenCaptureKit object as a `live` handle. The cost is
  `CaptureError.notListed` and one guard in `runScrolling`, both unreachable in the app. ______
- [ ] 5. C4 runs the real `TextRecognizer`; the first request after a restart can take about 24 s, inside the
  one-minute limit. The alternative is deferring phase-7b:81 to `COPYTEXT`. ______
- [ ] 6. recording-r2:351 is in part, not deferred: C8 adds its "captures are blocked while the prompt is up" clause to
  the existing held-prompt test. ______
- [ ] 7. recording-r1:105 needs `TMPDIRS`, not nothing: both halves of the line come after `recordingCanStart`. ______
- [ ] 8. The 16 deferred recording lines join `TMPDIRS` in seams.md, noted "also `TMPDIRS`, deferred in CT-4". Not
  joining leaves `TMPDIRS` at 14 lines and understates what it unlocks. ______
- [ ] 9. phase-2:32 and small-tweaks:13 name a `Saved` word the row no longer shows; their text stays and the marks
  cover what is still true. ______
- [ ] 10. coordinator-split:36, phase-6b:66 and phase-7c:182 keep naming `CAPSRC` for the origin each entry point
  builds, although `CAPSRC` landed here: no test drives those entry points into a save. ______
- [ ] 11. T10's `cardShows` leg, T9's `cause` and T21 go beyond the twenty tests the first review asked for. ______

## The plan's decisions, to confirm or overrule

The plan lists them at its end (`docs/superpowers/plans/2026-11-01-capture-seams.md`, Plan decisions). None changes
what a user could see, and none changes a number the design gives:
- [ ] The marks and seams.md follow the design's section 11 and the catalogue's mark tables; where the plan words a mark
  or an entry otherwise (the four extended marks take the catalogue's wording whole, phase-6b:105 is the form without
  C9), the decision says so. ______

## Observations
Write into the design's built notes: anything above that failed, and each call and decision confirmed or overruled.
