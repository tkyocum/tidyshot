# Recording R1 manual test checklist

Run after any change to `TidyShot/Recording/`, `AppCoordinator` (`recordScreen`, `recordFullscreen`,
`record(_:)`, `saveRecording`, `finishRecordingForQuit`, the Clop and upload paths for a `.file`
payload, the video branches of the card, Recent Captures, drag-out and Save As…), `UploadQueue`,
`S3Destination`'s file upload and download, or `ClopOptimiser.optimisedVideo`. Automated tests cover
the pure decisions (configuration and the 4096 cap, clock, limits, the end rule, the save plan), the
controller against a fake stream (stop order, timeout, first end wins, quit), the streamed hash and
file upload, Clop's acceptance rules, recovery of a leftover file, and the card, row, drag, naming
and thumbnail rules for a video, with the drag clean-up's wait while Copy File's reference is on the
clipboard. Everything here needs a real screen, Screen Recording, real windows, sleep, the network,
Clop or eyes. The 6a, 6b and 7b checklists still cover the capture, overlay and cover paths for
images; run them too after a change to those.

Several steps are probes: they run a small program next to the app, or read the app's log, and ask
you to write down what the system did. Those results settle the design's "Still to probe" list and
the nine gaps at the end. Fill each blank, then copy the results into the design's Probes section
(`docs/superpowers/specs/2026-10-21-tidyshot-screen-recording-design.md`) and take the two
bullets out of "Still to probe".

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted to that build
(the build is signed ad hoc, so every rebuild needs a new grant; note how it is signed in
`Config/Local.xcconfig`), "Show notification" and "Play sound" on in Settings > General, Allow URL
commands on, an upload destination that works, and Clop (direct or Setapp) installed and running.
You also need a Retina display, a second display, the 5K display for Large output, and a save
folder on a volume other than the startup volume (an external disk, or a disk image below). Quit
TidyShot, start from the defaults, then open it again:
```bash
for k in recordingFrameRate recordingRetina recordingSystemAudio recordingShowsCursor recordingCountdown \
         recordingFileNameTemplate hideDesktopIconsWhileCapturing desktopIconsHidden \
         KeyboardShortcuts_recordScreen KeyboardShortcuts_recordFullscreen; do
  defaults delete io.tky.tidyshot $k
done
```
A key that was never set prints `does not exist`, which is fine. The last two put `Record screen:`
back to ⌃⇧8 and clear `Record fullscreen:`, which a step below sets. `afterCaptureAction` and
`optimiseWithClop` are set by the steps that need them; put them back at the end.

Make the working folder, the probes and a disk image once.
```bash
mkdir -p ~/Desktop/rec-r1 && cd ~/Desktop/rec-r1
P=~/git/tidyshot/docs/superpowers/research/recording-probes
xcrun swiftc -O -target arm64-apple-macos26.0 -o record-window $P/record-window.swift
xcrun swiftc -O -target arm64-apple-macos26.0 -o record-stop-order $P/record-stop-order.swift
cat > windows.swift <<'SWIFT'
import CoreGraphics
// Prints the id, owner and title of every normal on-screen window.
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowLayer as String] as? Int) == 0 {
    print(window[kCGWindowNumber as String] as? Int ?? 0, window[kCGWindowOwnerName as String] as? String ?? "", "|",
          window[kCGWindowName as String] as? String ?? "")
}
SWIFT
xcrun swiftc -O -o windows windows.swift
hdiutil create -size 4g -type SPARSE -fs APFS -volname RecOff off && hdiutil attach off.sparseimage
```
The probes need Screen Recording for the shell you run them from (Terminal, or the terminal in your
editor), and an AppKit run loop, which they have. `./windows` lists the ids to pass as
`window <id>`. `/Volumes/RecOff` is the save folder off the startup volume. Detach it at the end:
`hdiutil detach /Volumes/RecOff`.

The files and the log:
```bash
C=~/Library/Containers/io.tky.tidyshot/Data
ls $C/tmp/Recording $C/tmp/Clop $C/tmp/Drag "$C/Library/Application Support/TidyShot/pending"
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
`tmp/Recording` holds a recording until a record points at its new place; `tmp/Clop` holds Clop's
work copies; `tmp/Drag` the drag-out copies; `pending` the upload-only and fallback files. The log
command prints the app's `Recording:` lines: every stream and output callback with
`recordedDuration`, and the recovery, Clop-skip and stop-wait lines. Call it "the log line" below.
`sips` does not read video; use `afinfo <file>` for the audio track (a `Data format` line with
`aac`; an error or no such line means no audio track) and QuickTime for the picture. A recording's
object is whatever the key template makes plus `.mp4` (`aSIS7x.mp4`).

The three after-capture actions are named in the picker as `Save and copy image` (the design's
`.save`), `Upload and copy URL` (`.upload`, "save and upload") and `Upload only, keep no local file`
(`.uploadOnly`).

## Settings and strings
- [ ] Settings > Capture has a `Recording` section after the Self-timer picker: `Frame rate` (`30 fps`, `60 fps`; 30 selected), `Resolution` (`Retina`, `Standard`; Retina) with the caption `Retina is capped at 4096 px on the longer side.`, `Record system audio` (off), `Show cursor in recordings` (on) and `Count down before recording` (on). The rows above it are in their own group. The Hide desktop icons caption reads `Covers desktop icons and widgets with the desktop picture during area, window, fullscreen, previous-area, All-in-One and self-timer captures, and area and fullscreen recordings. While covered, the desktop does not take clicks.`
- [ ] Settings > General has `Recording file name` under `File name`, `Recording {date} at {time}`, above the `Tokens:` caption. Emptying it and recording later gives a file called `Recording.mp4`. Under the copy toggle: `For recordings, the file is copied.` The upload-only caption begins `The file is kept inside TidyShot only until the upload succeeds`. The section that held `Images` is `Optimization`, with `Optimize images and videos with Clop` and the caption `Clop greatly reduces file size. It keeps its own copy of each image and video it optimizes, so long recordings also take space in Clop's cache.`
- [ ] Settings > Shortcuts lists `Record screen:` (⌃⇧8) and `Record fullscreen:` (empty) after `Capture text:`. Settings > Upload's key caption reads `The file's extension (.png or .mp4) is added.` The save-folder panel says `Choose where TidyShot saves screenshots and recordings.`
- [ ] The menu bar menu has `Record Screen  ⌃⇧8` and `Record Fullscreen` after `Capture Text`, both greyed while a screenshot capture runs.
- [ ] Settings persist. After the reset, `defaults read io.tky.tidyshot recordingFrameRate` prints `does not exist`: the six defaults are registered, not written, so a key exists only once its setting has been changed. Change each (`60 fps`, `Standard`, Record system audio on, Show cursor in recordings off, Count down before recording off, Recording file name `Clip {time}`), quit and reopen: the panes still show them, and `defaults read io.tky.tidyshot <key>` (one key per call) reads `60`, `0`, `1`, `0`, `0` and `Clip {time}` for `recordingFrameRate`, `recordingRetina`, `recordingSystemAudio`, `recordingShowsCursor`, `recordingCountdown` and `recordingFileNameTemplate`. Put them back with the reset loop (quit first) and reopen. A value other than 30 or 60 written by hand reads as 30 in the picker (`defaults write io.tky.tidyshot recordingFrameRate -int 45`, relaunch, then delete the key).
  (suite: AppSettingsTests.recordingDefaultsAreRegisteredNotWritten, .recordingSettingsPersistUnderTheirKeys,
  .aStoredFrameRateOtherThan30Or60ReadsAs30)

## Relaunch, then save and upload
The sandbox only lets TidyShot read a save-folder file after a relaunch if the upload holds the folder's scope. A test in the same launch as the folder choice passes even without that, so relaunch first.
- [ ] Settings > General > After capture = `Upload and copy URL`. Choose `/Volumes/RecOff` as the save folder (Choose…), quit TidyShot from the menu and open it again. Do not touch the save folder in this launch.
- [ ] ⌃⇧8, drag an area of about 800 x 500 pt, wait out the count-in and record 10 s with something moving, then Stop on the panel. A card shows the poster with a `play.fill` badge and `0:10`; `Recording saved` does not post (the upload shows its own state). The file `Recording <date> at <time>.mp4` is in `/Volumes/RecOff`, plays in QuickTime, is about 10 s, and its pixel size is the area at 2x.
- [ ] The card goes through `Optimizing…` if Clop is on, then uploads, and says `URL copied`. The clipboard holds the URL, and the URL plays in a browser. Write down the file size before and after Clop: ______ MB, ______ MB.
- [ ] Retry a failed upload. Record again, and before Stop turn Wi-Fi off. Stop, and wait more than 70 s (six attempts over about a minute) until the card says the upload failed. Turn Wi-Fi on, quit TidyShot and open it again, then Retry from Recent Captures (or Retry Failed Uploads in the menu). The upload finishes from the save-folder file on `/Volumes/RecOff`, without a folder prompt, and the link plays. Write down what you saw: ______
- [ ] Repeat the last step with `Upload only, keep no local file`: the file is in `pending` while it fails, a Retry after a relaunch finishes, and `pending` is empty afterwards.
  (suite: CoordinatorSaveTests.anUploadOnlyRecordingThatCannotUploadWaitsInPendingUntilARetry)

## Starting, stopping and the panel
Settings > General > After capture = `Save and copy image` unless a step says otherwise.
- [ ] Area: ⌃⇧8 and drag. The dashed frame outlines the area; the badge counts 3, 2, 1 over it; the panel is a bar of about 244 x 44 pt (280 with sound) beside the area with `0:00`, the highlights and bubble buttons, `Stop` and `Cancel`. The elapsed time counts up each second from the first frame. The menu bar icon is `record.circle`, and the menu's first item is `Stop Recording  ⌃⇧8`, with `Record Screen` and `Record Fullscreen` gone and every capture item greyed. Settings, Recent Captures and the Quit item still work.
- [ ] Neither the frame, the panel nor the count-in badge is in the file. The covers (below) are.
- [ ] Window: ⌃⇧8 and click a window. The count-in frames the window, there is no dashed frame during the recording, and the panel sits beside the window's starting frame and does not follow the window.
- [ ] Fullscreen: Record Fullscreen from the menu, with the pointer on the second display. The display under the pointer records, the badge is centred on it with no frame, and the panel is at the bottom centre of its visible frame, a little above the Dock or the screen edge.
- [ ] Stop each way, one recording each, whichever way it was started: the panel's Stop, ⌃⇧8, Record Fullscreen's shortcut (set one in Settings > Shortcuts first; the reset loop clears it), and `Stop Recording` in the menu. Each ends the recording once, plays the shutter, and saves one file and one card.
- [ ] The panel never takes focus. Click Stop while another app is frontmost: the other app stays frontmost and keeps its menu bar. Drag the panel by its background, and by the digits: it moves, and the recording does not show it moving.
- [ ] Escape does nothing during a recording (type it in a text editor that has focus). During the count-in, Escape cancels, and so do ⌃⇧8 and the fullscreen shortcut. After a cancelled count-in nothing is recorded, no file is made, the covers are gone and a new recording starts normally.
- [ ] An area smaller than 32 x 32 pt posts `Select a larger area to record.` (titled `Screen recording`) and records nothing. An area recording does not become the Previous Area: ⌃⇧6 still uses the earlier image capture's rect.
- [ ] The time turns orange at `5:00` and the recording goes on past it (leave one running for 5 minutes and a bit). At an hour it reads `1:00:00` (optional; read `RecordingClockTests` instead if you do not record that long).
- [ ] Frame rate 60 fps and Resolution Standard: record 10 s of motion at each. `Standard` is 1x pixels (an 800 x 500 pt area is 800 x 500 px). 60 fps plays smoothly. Show cursor in recordings off: no pointer in the file.
- [ ] After-capture action, each in turn: `Save and copy image` (file in the save folder, a file reference on the clipboard, `Recording saved` posts naming the file, a click reveals it); `Upload and copy URL` (file in the save folder, file reference meanwhile when `Also copy image` is on, the URL when the upload finishes); `Upload only, keep no local file` (the file goes to `pending` and is removed when the upload ends, the URL replaces the clipboard). Write down any difference: ______
- [ ] Panel buttons in a non-key panel: Stop and Cancel respond to the first click. The Cancel tool tip is `Discard the recording`.
- [ ] The Previous-area, Self-Timer and All-in-One screenshots still work after a recording, and ⌃⇧8 works again at once.

## Count-in off
- [ ] Settings > Capture > `Count down before recording` off. Open a Safari window with a page that has a visible title bar state (active title bar, traffic-light colours). ⌃⇧8 and click the Safari window. There is no badge, the recording starts about a tenth of a second after the click, Safari's title bar is active in the first frame (scrub to 0:00 in QuickTime), and typing in the Safari address bar during the recording reaches Safari and shows in the file. Turn the count-in back on afterwards.
- [ ] Record Fullscreen with the count-in off starts at once (it reads the content before and after, so allow a moment).

## Exclusions during a fullscreen recording
- [ ] Start Record Fullscreen. During the recording open the menu bar menu, Settings…, Recent Captures (hover the preview too), restore a closed card (Restore Closed Overlay), open a pin, open an editor on an earlier capture, and then stop from the menu. None of those TidyShot windows appears in the file, the panel included. Another app's windows appear as usual. Write down anything of TidyShot's that did show: ______
- [ ] The log line shows no `TidyShot is not in the shareable applications` line. (That line is the fallback path, which cannot be forced; it is checked by reading `ScreenRecordingDriver.fallbackFilter`.)

## Covers
- [ ] Hide desktop icons while capturing on, an icon on the desktop, a widget if you use them. Record an area over the desktop: the icons and widgets are hidden for the whole recording, and the covers are in the video as the desktop picture. While recording, clicking the desktop does nothing; a window above it takes clicks as usual.
- [ ] A window recording with Hide desktop icons while capturing on and the persistent `Hide Desktop Icons` menu item off: the covers go as soon as the selection returns the window, and the bare desktop takes clicks during the recording (the window is the only thing in the picture, so the covers would add nothing).
- [ ] The same with the persistent item on: its covers stay up through the window recording and afterwards. (suite, in
  part: DesktopCoverReasonsTests.theEndOfACaptureLeavesPersistent, .captureAndPersistentTogether; the controller keeping
  the covers up through a real window recording stays by hand)
- [ ] The covers are gone after Stop, after Cancel and after a cancelled count-in, with the persistent item off.
- [ ] A recording started with the setting off shows the icons.

## Cancel
- [ ] Cancel before 5 s: the recording is discarded at once, with no alert, no file in the save folder, no record and no notification. `tmp/Recording` is empty.
  (suite: RecordingControllerTests.cancelUnderFiveSecondsRemovesTheFileWithoutAsking,
  RecordingEndTests.discardingCancelRemovesAPlayableFileAndPostsNothing)
- [ ] Cancel from 5 s: the alert `Discard this recording?` / `<m:ss> of recording will be deleted.` shows with `Save` (the default) and `Discard`. The alert is not in the file. While it is up the lock and the covers stay.
- [ ] `Save` saves the recording as a Stop would. Return in the alert does the same. `Discard` removes it: no file, no record, no notification.
- [ ] Cancel at about 4.9 s and 5.0 s on a stopwatch: just under discards at once, at 5 s it asks. (suite:
  RecordingLimitsTests.cancelAsksFromFiveSeconds,
  RecordingControllerTests.cancelUnderFiveSecondsRemovesTheFileWithoutAsking,
  .cancelFromFiveSecondsAsksAfterTheWaitAndSaveKeepsTheFileAsStopDoes)
- [ ] While the alert is up, the recording has already stopped (the file is finished before you answer), so what you read in the alert is the length the file will have.
  (suite: RecordingControllerTests.cancelFromFiveSecondsAsksAfterTheWaitAndSaveKeepsTheFileAsStopDoes)

## Window changes
The rules hold whatever these show: a window that is minimised, hidden or on another Space keeps recording, and only a closed window ends the recording. These probes show what ScreenCaptureKit actually does. Run each, do the changes one at a time (about 8 s apart), and write down what is printed.

Probe 1, its own window. It opens a resizable, minimisable, closable window with a scrolling page, records it for 90 s and prints every callback with `recordedDuration`, and once a second whether the window is listed and on screen.
```bash
cd ~/Desktop/rec-r1 && ./record-window own.mp4 90
```
| Change | Callbacks printed | `recordedDuration` after | listed / onscreen |
|---|---|---|---|
| Resize larger | | | |
| Resize smaller | | | |
| Move | | | |
| Move to another display | | | |
| Minimise | | | |
| Hide (⌘H) | | | |
| Switch Space (⌃→) and back | | | |
| Close | | | |

After the stop and the finish callback the probe prints the file's duration, tracks and natural size: ______. A window resized during the recording should be scaled to fit the starting size and letterboxed, never stretched: ______

Probe 2, another app's window by id. Open a Safari or TextEdit window, `./windows` for its id, then:
```bash
cd ~/Desktop/rec-r1 && ./windows && ./record-window other.mp4 90 window <id>
```
| Change | Callbacks printed | `recordedDuration` after | listed / onscreen |
|---|---|---|---|
| Resize larger | | | |
| Resize smaller | | | |
| Move | | | |
| Move to another display | | | |
| Minimise | | | |
| Hide (⌘H) | | | |
| Switch Space and back | | | |
| Close | | | |

Probe 3, system audio from another app. Record a window with `audio` while another app plays a sound.
```bash
cd ~/Desktop/rec-r1 && ./record-window audio.mp4 12 audio window <id>
# in another shell, meanwhile:
for i in 1 2 3; do afplay /System/Library/Sounds/Submarine.aiff; done
afinfo audio.mp4
```
Does the file have a `soun` track? ______ Is the other app's sound in it (play it)? ______ (`excludesCurrentProcessAudio` leaves out only the probe's own sound, and the probe plays none, so there is nothing to check for it here.)

In the app, the same changes. Settings > General > After capture = `Save and copy image`. Record a window of another app with ⌃⇧8 (a Safari window), make each change, and read the log line after each recording.
```bash
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
| Change | Recording keeps going? | `Recording:` lines | Notification |
|---|---|---|---|
| Resize larger | | | |
| Resize smaller | | | |
| Move | | | |
| Move to another display | | | |
| Minimise (and restore) | | | |
| Hide (⌘H) (and unhide) | | | |
| Another Space (and back) | | | |
| Close | | | |

- [ ] Resize, move and move to another display keep recording; the file scales the window to fit its starting size and never stretches it.
- [ ] Minimise, hide and another Space keep recording (the panel's time keeps counting; the file has the window again after it returns, and while it is off screen the file shows the last frame or nothing new: write down which ______).
- [ ] Close ends the recording within about a second with `Recording stopped` / `The recorded window closed.`, and the file up to then is saved and plays. The card and the clipboard follow the after-capture action.
- [ ] Closing the window during the count-in, and moving it: closing it before the fresh content read posts `Screen recording` / `The window is no longer on screen.` and records nothing, with the lock and covers released. Moving it during the count-in records it at its new place (the size comes from its fresh frame). Write down what happened: ______

## Large output on the 5K display
- [ ] On the 5K display (5120 x 2880) with Resolution `Retina`, Record Fullscreen for 10 s. The file is 4096 x 2304 (QuickTime Player > Window > Show Movie Inspector shows the size; `mdls -name kMDItemPixelWidth -name kMDItemPixelHeight <file>` does too once Spotlight has indexed it), plays, and has the right aspect. Write down how long Stop took to the card: ______ s
- [ ] With Clop on, the upload optimises it (the card says `Optimizing…`, the object is smaller than the saved file). Write down the sizes: ______
- [ ] An area on the 5K display that is larger than 4096 px on its long side is capped the same way. `Standard` records at 2560 x 1440 and needs no cap.

## Display sleep
- [ ] Set the display-off timer to 1 minute (System Settings > Lock Screen > Turn display off when inactive, for the power source you are on). Record an area for 3 minutes with the mouse and keyboard untouched. The display stays on the whole time (the recording holds `idleDisplaySleepDisabled`), the file is 3 minutes, and after Stop the display sleeps on its own a minute later. Put the setting back.

## Sleep, lock and switch
The rules: a system sleep and a user switch stop and save the recording; a screen lock (⌃⌘Q) does not stop it. ScreenCaptureKit decides what really happens first, and the stop wait ends only on the output's finish or fail, or at 15 s of awake time.

Probe 4. `record-stop-order watch` records an area with audio for 180 s and prints every callback, each frame-status change, and at the end (or after the stream stops by itself) waits up to 15 s for the finish callback and prints the file. Run it once for each event below, doing the event about 20 s in.
```bash
cd ~/Desktop/rec-r1 && ./record-stop-order watch sleep.mp4
```
| Event | `didStopWithError` | `didFailWithError` | frame status changes | finish follows? how soon | file plays? |
|---|---|---|---|---|---|
| ⌃⌘Q (lock), then unlock | | | | | |
| Hot-corner display sleep, then wake | | | | | |
| System sleep (Apple menu > Sleep), then wake | | | | | |
| Lid close, then open | | | | | |
| Fast user switch, and back | | | | | |

A lid close sleeps the Mac unless it is in clamshell mode (power and an external display); write down which you had. A fast user switch needs a second account that is logged in. For a system sleep or a lid close, wait a minute before waking.

Is the file complete after each (its duration, tracks and size, as the probe prints)? ______ After a `didStopWithError`, did a finish or a fail follow, and how soon? Without one the app's stop wait runs its full 15 s: ______

In the app. Record an area (Settings > General > After capture = `Save and copy image`), do each event 20 s in, and read the log line afterwards.
```bash
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
| Event | Recording stopped and saved? | Notification | `Recording:` lines | Stop wait: at once, or `the stop wait timed out`? | File plays |
|---|---|---|---|---|---|
| ⌃⌘Q, unlock | keeps recording | | | | |
| Hot-corner display sleep, wake | | | | | |
| System sleep, wake | stops and saves | `Recording stopped` / `Your Mac went to sleep.` | | | |
| Lid close, open | stops and saves | | | | |
| Fast user switch, back | stops and saves | `Recording stopped` / `Another user took over the screen.` | | | |

- [ ] A lock keeps recording: after unlocking, the panel's time kept counting and the file covers the lock (a black or lock-screen picture is fine; write down which: ______). Stop works as normal.
- [ ] After a system sleep or a lid close, the file is saved on wake and plays. The 15 s stop timeout counts time awake only, so a Mac that slept for a minute before the finish does not delete the file on wake.
- [ ] The recording kept the Mac awake: with the idle sleep timer set short, an unattended recording does not sleep the Mac. A lid close still sleeps it.

## Quitting, logging out and crashes
Each row for an `Upload and copy URL` recording (`.upload`) and a `Save and copy image` recording (`.save`). Record for at least 10 s each time. The third row needs no save folder, so that Stop opens the folder panel: quit TidyShot, `defaults delete io.tky.tidyshot saveFolderBookmark`, open it again, and put the folder back afterwards.
| Event | `.save` result | `.upload` result |
|---|---|---|
| Quit from the menu during the recording | | |
| Log out during the recording (then log in) | | |
| Stop, then quit while the folder panel is open (no save folder set) | | |

- [ ] In every row TidyShot quits, with no hang and no extra prompt. With a save folder, the file is in the folder; `.upload` shows `Upload failed` with `Upload was interrupted.` in Recent Captures after the relaunch, and Retry uploads it. With no folder, or with the panel open at the quit, the file is in `pending/<id>.mp4` with a record (`Kept in TidyShot`), not in `tmp/Recording`. No card and no notification show during the quit. The shutter and the clipboard rule still apply.
- [ ] Quit with the folder panel open: the quit closes the panel as its Cancel button would (the first real test that `cancel(nil)` closes a sandboxed open panel), and the file takes the `pending` path. Write down what the panel did: ______
- [ ] Quit during the count-in records nothing: no file, no record, no panel. (suite, in part:
  CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled,
  .aQuitCancelsTheCountInStopsTheRecordingAndWaitsForTheNotices; `record()` is not driven, so no file, no record and no
  panel stay by hand)
- [ ] Quit with an unsaved editor open and a recording: the editor's save sheet comes first. Cancel in the sheet cancels the quit and the recording runs on. Choosing Save or Don't Save then stops and saves the recording.
- [ ] A Cancel's question held by a quit: with an unsaved editor open, record for more than 5 s, quit (the editor's save sheet is up), press Cancel on the panel, then answer the sheet. The quit finishes and the recording is saved in quit mode, not discarded, and it does not hang waiting for the discard question.
- [ ] A second quit during a held quit does nothing (no second reply).
- [ ] A log out during a held quit is cancelled. Record, open an unsaved editor, Quit from the menu (the editor's save sheet is up), then Log Out from the Apple menu. The second terminate gets `.terminateCancel`, so macOS cancels the log out (it usually names the app that cancelled it); the held quit goes on, and answering the sheet with Save or Don't Save quits TidyShot with the recording saved. Log out again afterwards if you meant to. Write down what macOS showed: ______
- [ ] `kill -9` mid-recording. Record for at least 10 s, then `pkill -9 -x TidyShot`. Open TidyShot again: `Recovered a recording` posts with `<file name>, <m:ss>. Find it in Recent Captures.`, no card shows, the recording is in Recent Captures with its poster, and it plays (QuickTime) at about the recorded length. `tmp/Recording` is empty afterwards and the file is in `pending`. The log has `Recording: <name> recovered as <name>`. Write down the recorded length against the recovered length: ______
- [ ] `kill -9` between Stop and the save. Choose a long recording (60 s or the 5K display) with the save folder on `/Volumes/RecOff`, so the move takes a moment. Press Stop and run `pkill -9 -x TidyShot` straight after (type the command first). Relaunch, then look in Recent Captures, `/Volumes/RecOff`, `tmp/Recording` and `pending`. One of three things happened; each is expected, and the recording plays wherever it is:
  1. The kill came before the move finished. `Recovered a recording` posts and the recording is in `pending` with its record, as above. The move to another volume is a copy, so a copy of it, partial or complete, may also be left in `/Volumes/RecOff` with no record; note it if so.
  2. The kill came after the record. The recording is in `/Volumes/RecOff` with its record in Recent Captures, and nothing posts.
  3. The kill came in the few milliseconds between the move and the record (design, Where the file lands, The tmp file). The recording is in `/Volumes/RecOff` and plays, but Recent Captures does not list it and nothing posts. (With no save folder it would be in `pending` with no record, and nothing finds it.)

  Write down which, and the files you found: ______
- [ ] A leftover that does not play (`echo junk > "$C/tmp/Recording/x.mp4"`, then relaunch) is removed with `Recording: x.mp4 could not be played, removed`.
  (suite: RecordingRecoveryTests.aLeftoverThatDoesNotPlayIsRemovedAndLogged; the relaunch and the junk file are the
  set-up)

## Upload resilience
Use `Upload only, keep no local file` for the first and `Upload and copy URL` for the others, with a recording long enough for the upload to take a minute (a 5K or 3 minute recording; cap the upload speed with Network Link Conditioner if needed).
- [ ] A long upload left idle past the sleep timer finishes: start the upload, leave the Mac alone for longer than the display and idle sleep timers (the upload holds an activity, so the Mac does not sleep). Write down whether it finished: ______
- [ ] Wi-Fi off for 10 s mid-upload recovers without `Upload failed`: the progress stalls, then goes on (it restarts from byte 0). Write down what the card showed: ______
- [ ] Sleep and wake mid-upload (Apple menu > Sleep, wake after a minute): the upload finishes or fails and retries; write down which: ______
- [ ] The upload never loads the file into memory: with Activity Monitor open, TidyShot's memory stays near its idle size during a 1 GB upload.
- [ ] Delete (and confirm) during the upload cancels it and removes the file, the record and any object already uploaded. Delete during `Optimizing…` cancels at once, and `tmp/Clop` is empty afterwards.
  (suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey,
  CoordinatorClopTests.deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap)
- [ ] R4 changed this (was: refused over 5 GiB). A recording over 625 GB is refused (`Not uploaded` / `The recording is larger than 625 GB, too large to upload.`) and the record is kept as `.none`. This cannot be recorded by hand in reasonable time; `RecordingLimitsTests`, `MultipartPlanTests` and `RecordingSavePlanTests` cover the boundary and the plans, and the hand check is skipped.
  (suite, in part: MultipartPlanTests.partSizeIsNilAbove625GiB, RecordingSavePlanTests.oversizedNotice,
  .oversizedSaveFolderFileStays, .oversizedPendingFileMovesIntoTheSaveFolder; the coordinator's `refuseOversizedUpload`
  has no test, and the line's hand check is already skipped)

## Clipboard after the upload
- [ ] Settings > General > After capture = `Upload only, keep no local file`. Record, Stop, and while the upload runs copy some text in another app. When it finishes, the text is still on the clipboard, `Uploaded` posts with the URL as its body and `Click to copy the link.` as its subtitle, the card says `Uploaded`, and a click on the notification copies the link without opening it.
- [ ] With nothing copied in between, the URL replaces the clipboard, `Uploaded, URL copied` posts, and the card says `URL copied`.
  (suite, in part: CoordinatorUploadTests.anUploadedRecordingReplacesTheClipboardOnlyWhileItHoldsWhatTheSaveLeft,
  QuickAccessModelTests.uploadedSaysWhetherTheLinkWasCopied; the title `Uploaded, URL copied` is the live notifier's and
  stays by hand)
- [ ] With `Upload and copy URL` and `Also copy image` on, the clipboard holds the file reference meanwhile and the URL after, as long as nothing else was copied.
  (suite: CoordinatorSaveTests.aRecordingsURLReplacesItsFileReferenceOnlyWhileTheClipboardHoldsIt)
- [ ] Retry an interrupted upload after a relaunch (TidyShot has no count for it): the clipboard counts as changed, so the upload finishes with `Uploaded` and the clipboard is left alone.
  (suite: RecordingSavePlanTests.urlReplacesTheClipboardOnlyWhenItIsUnchanged,
  CoordinatorUploadTests.anUploadedRecordingReplacesTheClipboardOnlyWhileItHoldsWhatTheSaveLeft)
- [ ] Screenshots keep today's behaviour: their URL always replaces the clipboard. (suite:
  CoordinatorUploadTests.aScreenshotsURLReplacesTheClipboardEvenAfterACopyElsewhere)

## Copy File
- [ ] Copy File on a pending video (`Upload only` while it uploads) from the card's menu, then wait for the upload to end and paste in Finder: the file pastes (it is a staged copy in `tmp/Drag`, not the pending file that the upload removed).
  (suite: CoordinatorDragOutTests.aCopyFileStageOfAPendingVideoOutlivesItsUpload)
- [ ] Let the card close (or close it), wait more than a minute and paste again: the file still pastes, because the one-minute clean-up waits again, a minute at a time, while the clipboard still holds its Copy File reference (Gap 7). `ls $C/tmp/Drag/*` still lists the copy. Now copy some text in another app and wait more than a minute: `tmp/Drag` no longer has the copy.
  (suite: CoordinatorDragOutTests.theCleanUpWaitsWhileTheClipboardHoldsTheCopyFileReference,
  DragCleanupTests.theClipboardStillHoldingCopyFilesReferenceWaitsAgain, .aClipboardThatMovedOnRemovesTheFolder)
- [ ] With no card showing for it, Copy File from the Recent Captures row of a `Kept in TidyShot` video (its file stays in `pending`) and paste: the file pastes. Copy some text and wait more than a minute: the copy has gone from `tmp/Drag`, though no card closed after the Copy File.
  (suite: CoordinatorDragOutTests.aCopyFileWithNoCardSchedulesItsOwnCleanUp)
- [ ] Close a `Kept in TidyShot` video's card (restore it first if it is closed) and, within the minute, Copy File from its row: the file pastes, and still pastes a minute later (Copy File cancels the clean-up that was due, as a press does, and schedules its own).
  (suite: CoordinatorDragOutTests.aCopyFileWithinTheMinuteReplacesTheCloseCleanUp)
- [ ] Copy File once more, then quit and reopen TidyShot without copying anything else: the launch sweep of `tmp/Drag` removes the copy, so a paste finds no file (expected; write down what Finder does: ______).
- [ ] Copy File on a recording in the save folder puts the file itself on the clipboard. (suite:
  CoordinatorRecordActionsTests.copyFilePutsASavedRecordingItselfAndNeedsALocalFile)
- [ ] Recent Captures: a video row has `Copy File` (`doc.on.doc`) where Copy Image is for screenshots. A click on the row copies the link, or the file when there is none.
- [ ] With `{counter}` in the Recording file name template, press a pending video's card for a drag after Copy File: the clipboard's file still pastes (the staged copy is reused under the name it has).
  (suite: CoordinatorDragOutTests.aDragPressAfterCopyFileReusesTheStagedCopy,
  DragFileStoreTests.aVideoStageReusesAMatchingCopyUnderAnotherName)

## Clop
Settings > General > Optimization > `Optimize images and videos with Clop` on, Clop running. The `Clop:` log lines come from `NSLog`, which `log show` prints as `<private>` on this Mac (the `Recording:` lines use `Logger` and read fine). To read them, start TidyShot with its stderr in a file. Quit TidyShot from its menu first: `open -n` starts a new copy even while one runs, and two copies would both take the shortcuts. Then `open -n --stderr ~/Desktop/rec-r1/tidyshot.err ~/git/tidyshot/.build-rel/Build/Products/Release/TidyShot.app`, check that `pgrep -x TidyShot` prints one id, and later `grep 'Clop:' ~/Desktop/rec-r1/tidyshot.err`. If that file stays empty, say so in the Observations and judge by the object's size and tracks instead.
- [ ] The queue. Record about 2 minutes (more than a 20 s Clop run) and Stop. While the card says `Optimizing…`, take a screenshot (⌃⇧4). Write down whether the screenshot uploads at once, times out and uploads the original, or waits for the video: ______ (Clop's image and video requests are on separate queues in TidyShot; if Clop answers one port request at a time, an image request sent during a video times out after 32 s and the original uploads. That is the accepted worst case.)
- [ ] Audio. Settings > Capture > Record system audio on, Clop on, and Clop's own "Remove audio on optimised videos" preference on. Record a window or area with sound (`afplay`), upload, then `curl -s -o ~/Desktop/rec-r1/out.mp4 "<url>"; afinfo ~/Desktop/rec-r1/out.mp4`. The object still has an audio track and plays with sound. If the sound is gone, the `Clop:` line says `Clop: the result lost its audio, uploading the original`, and the original uploaded (the object is as big as the saved file). Write down which: ______
- [ ] A silent recording: the same, with no audio track on either side, is accepted and smaller (a 79 % saving on the probe's scrolling page).
- [ ] Cleanup. `ls $C/tmp/Clop` is empty after an optimised upload, after a failed upload (Wi-Fi off, wait for `Failed`), and after a Delete during optimisation. A Retry runs Clop again from the original.
  (suite, in part:
  CoordinatorClopTests.aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal,
  .deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap; by hand: the real container's tmp/Clop
  and the launch sweep of it (`TMPDIRS`))
- [ ] Clop off: the original uploads and the card never says `Optimizing…`. Clop not running (quit it): the original uploads, TidyShot does not launch Clop, and the `Clop:` line reads `Clop: Clop is not running, uploading the original`.
  (suite: CoordinatorClopTests.aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning)
- [ ] With the `tmp` volume short of space (not testable by hand), the line `Clop: not enough free space, uploading the original` is read from the code and its test.
  (suite, in part: ClopOptimiserTests.notEnoughFreeSpaceSkipsClop; the test asserts the outcome
  `.original(.notEnoughSpace)` only, so the log text `Clop: not enough free space, uploading the original`
  (ClopOptimiser.swift:29, logged at AppCoordinator+Upload.swift:456) stays a code read)

## Cards and Recent Captures
- [ ] A card, with a local file: the poster with the badge and the duration (`0:42` form), click opens the file in QuickTime (tool tip `Open`), the side column has only Delete (no Annotate, no Pin to screen), and the right-click menu has `Copy URL` (once uploaded), `Copy File`, `Save As…`, `Reveal in Finder`, `Close` and `Delete…`, and no Copy Image, Annotate or Pin to Screen.
- [ ] A card for an upload-only video that finished: a click opens the URL. A video with neither a file nor a link does nothing on click.
- [ ] A card for a temporary file with `.none` shows `Kept in TidyShot` and `Not in your save folder. Use Save As… to keep a copy.`, not a green `Saved`. Get one by cancelling the folder panel (see Save folder problems). A click on its poster opens the `pending` file in QuickTime.
- [ ] Recent Captures: the row shows the poster with the badge, a `film` symbol for a video with no stored thumbnail, `· Optimizing…` while Clop runs; the hover preview shows the stored thumbnail at its own size; there is no Annotate and no Copy Image button.
- [ ] Annotate and Pin are absent everywhere for a video: the card, its menu, the row and the Recent Captures menus. (`Videos cannot be annotated.` is a safety net that nothing in the UI reaches.)
  (suite: QuickAccessModelTests.aVideoHasCopyFileInPlaceOfTheImageActions,
  RecentCaptureFormattingTests.aVideoHasNoImageActions)
- [ ] Save As… from the card. To a new file: a copy appears, `Saved` posts. Over an existing file, on the same volume and on `/Volumes/RecOff`: the file is replaced (the replacement-folder step must work under the sandbox across volumes; write down what happened: ______). With no local file and no drag copy: `Saving a copy…` / `Downloading <key>` posts and the download lands in the file.
- [ ] Drag a card with a local file into Finder and Slack or Mail: the file `Recording ….mp4` arrives. A second press, the click that opens the file, and the drag itself copy a large file across volumes once (watch `tmp/Drag`).
- [ ] R4 changed this (was: cannot be dragged). Dragging an uploaded video with no local file and no drag copy downloads it first, with progress on its card (see `recording-r4-manual-checklist.md`); Restoring its card still starts no download.
- [ ] Delete removes the save-folder file, the pending file and the uploaded object, as for a screenshot. (suite:
  CoordinatorDeleteTests.deleteRemovesTheObjectTheFileTheThumbnailAndTheRow)
- [ ] Retention (optional): quit TidyShot, back up `history.json`, set the `timestamp` of an uploaded video to 60 days ago and open TidyShot again. The record is dropped as any capture's is, its thumbnail goes, and its save-folder file stays. A video that is `Kept in TidyShot` (its only copy is in `pending`) is never dropped. Put `history.json` back.
  (suite: CoordinatorDeleteTests.retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads,
  HistoryStoreTests.pruningKeepsUploadOnlyCapturesThatWereNeverUploaded)

## Restore
- [ ] Restoring an uploaded upload-only video's card after its drag folder is gone (wait a minute past the card closing, or delete `tmp/Drag`) starts no download (check Activity Monitor/Network for a transfer). R4 changed the rest (was: the card cannot be dragged): a drag from that card downloads the file first (see `recording-r4-manual-checklist.md`). Save As… on that card downloads to the file you choose.
  (suite, in part: CoordinatorSaveAsTests.anUploadOnlyVideosSaveAsDownloadsToTheChosenFile, the Save As… sentence,
  CoordinatorDragOutTests.aDragOfAShowingUploadedRecordingStartsOneDownload, the drag sentence; by hand: restoring the
  card starting no download (`SCREENS`), Activity Monitor)
- [ ] Restore Closed Overlay brings back a video's card with its poster, its state and `Copy File` if there is a local file.

## No destination
Settings > Upload with no complete destination (or clear the credentials with Forget Credentials). The warning posts once per launch.
- [ ] `Upload and copy URL`: the recording is saved exactly as `Save and copy image` would (file in the save folder, `.none`), a file reference is on the clipboard whatever the copy settings say, `Recording saved` posts, and the warning `Upload not configured` / `Set up a destination in Settings > Upload. The recording was saved and is on the clipboard as a file.` posts.
  (suite: CoordinatorSaveTests.uploadWithNoDestinationSavesTheRecordingAndCopiesItsFile,
  RecordingSavePlanTests.uploadWithNoDestinationIsSavedAndCopiedAsAFile)
- [ ] `Upload only, keep no local file`: the file goes to `pending` with a failed state, nothing is on the clipboard, `Recording saved` does not post, and the warning reads `Set up a destination in Settings > Upload, then retry from Recent Captures. TidyShot keeps the recording until then.` After setting a destination, Retry uploads it.
  (suite: CoordinatorSaveTests.anUploadOnlyRecordingThatCannotUploadWaitsInPendingUntilARetry,
  RecordingSavePlanTests.uploadOnlyWithNoDestinationWaitsInPendingWithNothingCopied)

## Save folder problems
- [ ] No save folder set, `Save and copy image`: the folder panel opens after Stop. Cancel it: `Not saved to a folder` posts with `No folder was chosen. TidyShot keeps the recording. Use Save As… on its card.`, the file is in `pending`, the card says `Kept in TidyShot`, and the clipboard has a reference to the pending file. For `Upload and copy URL` the second sentence is `The recording uploads without a local copy.`
- [ ] A save folder that is gone since the launch (detach `/Volumes/RecOff` while TidyShot runs), a read-only folder (`chmod a-w`) and a full volume (a small disk image filled up) each give the same fallback with the error's description, never a lost file. Write down the descriptions: ______
- [ ] A clash: set Recording file name to `Clip` and record twice into the same folder. The second file is `Clip 2.mp4` and the first is untouched. Put the template back.
  (suite, in part: SaveLocationMoveTests.aClashGetsTheNextNumber; that `saveRecording` places a recording named by the
  template through it is a code read and stays by hand)

## The nine gaps, to confirm or overrule
The plan filled these where the design was silent; each was built as written. Write `confirm` or `overrule` and why, then copy the result to the design's Built notes.
- [ ] 1. Free space: `tmp/Recording` is created just before the 2 GB check; a fresh container is checked too; a folder that cannot be created gives `Recording failed`; an unreadable free-space value counts as enough, with a log line; the 2 GB check runs before the selection overlay, so a full disk refuses before you select. (Hand check: none possible; read it from `RecordingLimitsTests`.) ______
- [ ] 2. Extra parameters: `saveRecording(_:intent:stopNotice:mode:)` and `optimisedVideo(at:duration:scope:)`. Internal; nothing to see. ______
- [ ] 3. Counter: for a recording's upload, `{counter}` is drawn after the 625 GB check (R4; was 5 GiB), just before the enqueue. With `{counter}` in the key template, two recordings uploaded in a row get consecutive keys, and a recording deleted during `Optimizing…` leaves no gap (a refused upload would not either; that cannot be reached by hand).
  (suite: CoordinatorClopTests.deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap) ______
- [ ] 4. Fallbacks: `.upload` with no destination falls back exactly as `.save` (a forced file reference, `.none`); a `.save` fallback's clipboard reference points at the pending file; over 625 GB (R4; was 5 GiB), where the file is decides: a pending file moves into the save folder and a save-folder file stays.
  (suite: RecordingSavePlanTests.uploadWithNoDestinationFallsBackAsSave, .saveFallbackKeepsTheRecordingInPending,
  .oversizedSaveFolderFileStays, .oversizedPendingFileMovesIntoTheSaveFolder) ______
- [ ] 5. Quit mode skips only the folder prompt, Clop, the upload, the card, the notifications and the not-configured warning; the clipboard rule and the shutter still apply.
  (suite, in part: CoordinatorSaveTests.quitModeSkipsTheCardTheUploadAndTheNoticesForEveryAction,
  RecordingSavePlanTests.quitModeForEachAction; by hand: the quit itself, a folder panel open at the quit, and
  `.upload`'s `Upload failed` and Retry after the relaunch) ______
- [ ] 6. Strings: `<reason> The recording is still at <path>.` when even the rename failed (not reachable by hand); `Recovered a recording` reads `<file name>, <m:ss>. Find it in Recent Captures.` and shows no card; the recovered record's time is the file's creation date. ______
- [ ] 7. Copy File's drag copy outlives the upload and the card: a pending video's staged copy is kept at `.uploaded`, and `scheduleDragCleanup` waits again while the clipboard still holds the reference, then removes the copy once the clipboard has moved on. A Copy File with no card schedules the same clean-up. (See Copy File.)
  (suite: CoordinatorDragOutTests.aCopyFileStageOfAPendingVideoOutlivesItsUpload,
  .theCleanUpWaitsWhileTheClipboardHoldsTheCopyFileReference, .aCopyFileWithNoCardSchedulesItsOwnCleanUp,
  DragCleanupTests.theClipboardStillHoldingCopyFilesReferenceWaitsAgain) ______
- [ ] 8. Panel geometry: 172 x 44 pt for a window recording without sound, 244 x 44 for an area or fullscreen one (R3); the fullscreen panel sits `ScrollPanelGeometry.gap` above the bottom of the visible frame. Is the bar the right size and place? ______
- [ ] 9. Start races: the quit hold's count-in phase covers the whole hand-off, so a quit between the selection and the first frame records nothing; a window or display that goes between the hand-off's last read and the driver's own read gives `Recording failed` / `The window is no longer on screen.` or `The display is no longer connected.`
  (suite: QuitHoldTests.everyRecordingPhaseButIdleHolds,
  CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled,
  RecordingControllerTests.aStartThatThrowsFailsWithItsDescriptionAndNoFile, .startErrorsSayWhatWentWrong) ______

## Regression
- [ ] ⌃⇧1 to ⌃⇧7 behave as in the 6a, 6b and 7b checklists after a recording, with and without Hide desktop icons.
- [ ] A screenshot's save, upload, Retry, Delete, Save As… and Copy Image are as before; a PNG still gets `.png` and `image/png`.
  (suite: CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse,
  CoordinatorSaveTests.aCaptureWithTheOverlayOffShowsNoCardAndStillUploads,
  CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey,
  CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject, CaptureRecordTests.mediaKindTypes,
  UploadQueueTests.uploadsAndReportsPublicURL,
  CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt)
- [ ] Old history (a `history.json` from before R1) loads, with every record an image. (suite:
  CaptureRecordTests.historyWithoutMediaKindDecodesAsImages)
- [ ] The Recent Captures menu opens at once with a video among the rows.
- [ ] Quit TidyShot with nothing recording: it quits at once. (suite: QuitHoldTests.idleWithNoUnsavedEditorDoesNotHold)

## Observations
Write these into the design's Probes section (and the Built notes for the gaps):
- The window-change probe results, own and another app's window, with what the file does for a window that is off screen.
- Whether a window recording with `audio` carries other apps' sound.
- What `didStopWithError`, `didFailWithError` and the frame status reported for ⌃⌘Q, a display sleep, a system sleep, a lid close and a fast user switch; whether a finish or a fail followed each `didStopWithError`, and how soon; whether each file played. Then whether the app's 15 s stop wait ran its full length for any of them.
- The `Optimizing…` queue behaviour for a screenshot during a video, Clop's behaviour with `removeAudio` against its own preference, and the file sizes before and after.
- Whether the sandbox let Save As… replace a file on another volume.
- Whether `cancel(nil)` closed the open panel at a held quit, and what the Cancel-then-quit case did.
- The 5K recording's size, Clop's result for it, and the time Stop took.
- Anything above that failed.
