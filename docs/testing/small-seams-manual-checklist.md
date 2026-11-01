# Small seams manual checklist

Run after the small seams phase (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`), and after any
later change to `AppEnvironment.clopOptimiser`, `isClopRunning`, `chooseSaveAsURL` or `recordingLog` and their live
values, to `askSaveAsTarget`, or to a `Recording:` log line. The suite now runs Clop through `world.clop`, the card's
Save As… panel through `world.saveAsChooser` and the coordinator's `Recording:` lines into `world.recordingLines`, and
the phase-7-clop, recording-r1 to r4, phase-6a, coordinator-split, coordinator-harness and small-tweaks checklists mark
46 more lines `(suite …)`, 28 in full and 18 in part. The three live values never run in the suite
(`AppEnvironment.live()` builds `AppSettings.shared`, the Keychain store and the notifier), so what is left here is the
real Clop, the real panel and the real log: that each does what it did before the seam.

## Checks

- [ ] 1. The real Clop path. With Clop running and `Optimize with Clop` on, a capture's upload shows `Optimizing…` and
  the row shows the smaller size; an MP4 recording does the same. Quit Clop and capture: the original uploads, the log
  has `Clop: Clop is not running, uploading the original`, and Clop is not launched.
- [ ] 2. The real panel. Save As… on a card while another app is frontmost: the panel opens in front of it, with the
  capture's name in the save folder. Cancel writes nothing; Save writes the copy and posts `Saved`. Save As… on an
  upload-only recording's card downloads to the chosen file.
- [ ] 3. The real log. `stop-recording` with nothing running, then
  `log show --last 5m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`: one `did nothing, no
  recording is running` line, public, not `<private>`. Then `echo junk > "$C/tmp/Recording/x.mp4"`, relaunch, and the
  same command shows `Recording: x.mp4 could not be played, removed`.

## The design's calls, to confirm or overrule

The design lists them in section 10. Write `confirm` or `overrule` and why; an overrule goes in its built notes.
- [ ] 1. `CLOP` is a protocol, `ClopOptimising`, on the environment, not the concrete optimiser over a fake transport,
  and `isClopRunning` is `() -> Bool`, not `() -> String?`. Overrule only to exercise the optimiser's file checks in
  coordinator tests; `ClopOptimiserTests` already does. ______
- [ ] 2. `LOG` is the coordinator plus `RecordingRecovery.scan`. The mute sweep is not threaded and `RecordingExtras` is
  left to `EXTRAS`. Two log members, `log` and `recordingLog`, for the privacy split at the call site. ______
- [ ] 3. `FakeDestination.download(key:to:)` records and writes. A later Trim test through
  `downloadAndPresentTrimWindow` would then get a file under the real `tmp/`, which is `TMPDIRS`' business. ______
- [ ] 4. SAVEAS 9 and 10 are new tests on CT-2's helpers, not in-place extensions of CT-2's tests. In place, the suite
  line would be 2350, not 2352. ______
- [ ] 5. `aSaveAsWhoseCaptureIsDeletedWhileThePanelIsUpWritesNothingAndLogsIt` is included: the deleted-while-open
  branch of `askSaveAsTarget`, which covers no line. ______
- [ ] 6. recording-r1:340 and recording-r2:670 are full: Save As… is the new test, and each other verb has an existing
  test. If a verb has none for a screenshot, the line becomes part. ______
- [ ] 7. recording-r1:263 is full, on the reading that the relaunch and the junk file are set-up; `start()` handing
  `scan` the sink is read from the code, not driven (`TMPDIRS`, `LAUNCH`). ______
- [ ] 8. coordinator-harness:27's wording stays, although the mark makes its "the suite pins the state, not the
  `RecordingLog` text" history. ______
- [ ] 9. phase-6a:169 and :173 are reached by SAVEAS test 1 but are not among the 49 lines; they stay unmarked. ______
- [ ] 10. CLOP T7 enters at `finishSave`, not `save(_:intent:)`, which no test can call (`CaptureTarget` holds an
  `SCDisplay` or `SCWindow`). ______
- [ ] 11. seams.md keeps equal-Lines seams in their old table order, and recording-r4:192 joins no seam: its by-hand
  part, the one selection on screen, is the drawn UI. The order of the three tasks (CLOP, SAVEAS, LOG) is free. ______

## The plan's decisions, to confirm or overrule

The plan lists them at its end (`docs/superpowers/plans/2026-10-31-small-seams.md`, Plan decisions). None changes what
a user could see, and none changes a number the design gives:
- [ ] The marks and seams.md follow the design's section 11 and the catalogue's mark tables; where the plan words a mark
  otherwise (recording-r1:313 names its drag test, recording-r4:192 keeps the catalogue's note inside the test list),
  the decision says so. ______

## Observations
Write into the design's built notes: anything above that failed, and each call and decision confirmed or overruled.
