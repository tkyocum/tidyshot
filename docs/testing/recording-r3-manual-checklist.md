# Recording R3 manual test checklist

Run after any change to `TidyShot/Recording/Bubble/` (`CameraDevices`, `CameraChoice`, `BubblePlacement`,
`CameraRunState`, `CameraSession`, `WebcamBubblePanel`), `TidyShot/Recording/Clicks/`
(`ClickHighlightRule`, `ClickRingTiming`, `ClickMonitor`, `ClickRingOverlay`), `RecordingExtras`,
`RecordingExclusions` and `makeFilter`, the controller's two bar states, the chrome, the panel's bars,
`RecordingNoticeOrder`, `GIFMaker` and `GIFPaletteBuilder` (`reserving:`), `AppCoordinator`
(`+Recording`'s prompts, resolve, hand-off, `RecordingExtras` and the notes, and `requestAccessFromSettings(_:)`),
`CaptureSettingsView`, `URLCommandHandler`'s refusal, or the entitlements and Info.plist keys in
`project.yml`. Automated tests cover the pure decisions (the click rule, the ring's timing, the reserved GIF
colours, the bubble's placement, drag and size steps, the camera's run state and loss rules, the camera
choice, its notes and the bar button's state, the settings layout and keys, the options snapshot, the
filter's sets, the bar's four widths, the controller's two toggles, the filmed set and the notes' order,
the prompts' steps and the capture refusal, the ring overlay's and the bubble panel's properties on
windows that are never shown, and the highlighter over fakes). Everything here needs a real screen,
Screen Recording, a camera, real windows and clicks, or eyes. No test opens a camera, installs a monitor or
makes a recording. The R1 and R2 checklists (`recording-r1-manual-checklist.md`,
`recording-r2-manual-checklist.md`) still cover starting, stopping, GIF, the microphone, mute, Trim and
quitting; run them too after a change to those.

Several steps are probes: they run a small program next to the app, or read the app's log, and ask you to
write down what the system did. Fill each blank, then copy the results into the R3 design's Probes section
(`docs/superpowers/specs/2026-10-24-tidyshot-screen-recording-r3-design.md`) and mark the item done in its R3
built notes.

## Held gates (read this first)

Nothing is held. G1 (the click monitor), G2 (windows made at the start) and G3 (the camera picker) passed
on 2026-10-27 (design, Probes), so `ClickMonitor`, the start's wiring and the bar's reach to the
highlighter are built. What is left needs Tim, because none of it could run unattended: the Release build
has no Screen Recording or Camera grant, and a grant is Tim's to give.

- **G4, the camera's loss.** No probe run saw a loss notification. The app treats every session error,
  interruption and stop that TidyShot did not ask for as a loss and posts `Camera lost`. The Camera loss
  section below is the first test of that. A notification that never fires, one that fires with no loss, or
  a camera that does not come back on its own goes to Tim, and the note's wording may change.
- **G5, the budget.** The Budget section below measures TidyShot's own CPU and memory. The probe's 3.0 to
  4.7 % CPU at 720p was an upper bound, and the iPhone went over 5 % at times (3.3 to 5.4 %). A number over
  the design's budget goes to Tim; the sizes and the format do not change.
- **P2 and C3** were not run. P2 is informational; C3 is the first camera prompt, below.
- **The hand checks** in every section below have not run.

## Setup

A fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release
-derivedDataPath .build-rel build`), signed ad hoc, so every rebuild needs a new Screen Recording grant (see
`Config/Local.xcconfig`). Give it these:
- **Screen Recording** in System Settings > Privacy & Security.
- **Camera.** Do not grant it by hand. The first prompt is C3's check, so run `tccutil reset Camera
  io.tky.tidyshot` first, and let the prompt ask. (This step is Tim's; nothing else runs `tccutil`.)

"Show notification" and "Play sound" on in Settings > General, and an upload destination that works. You also
need the Logitech Brio 500 and the iPhone (Continuity Camera, named `TKY Camera`), the 5K display and the
MacBook Pro's own display for the display checks, a fullscreen app (Safari's fullscreen is enough) with the
Dock showing on the display, the RODE AI-1 for the lip-sync check, and Safari or QuickTime Player for playback.
Only one TidyShot may run at a time. Quit TidyShot, start from the defaults, then open it again:
```bash
for k in recordingClickHighlights recordingWebcamBubble recordingCamera recordingCameraName \
         recordingBubbleSize recordingBubbleInsetRight recordingBubbleInsetBottom; do
  defaults delete io.tky.tidyshot $k
done
```
A key that was never set prints `does not exist`, which is fine. TidyShot reads its settings at launch, so
quit it first and open it again after changing a key by hand. Put the format, frame rate and microphone back
to what a step needs; the R2 checklist's reset loop does the rest.

Make the working folder and the probes once.
```bash
mkdir -p ~/Desktop/rec-r3 && cd ~/Desktop/rec-r3
W=~/Desktop/rec-r3
P=~/git/tidyshot/docs/superpowers/research/recording-probes
xcrun swiftc -O -target arm64-apple-macos26.0 -o $W/r3-clicks $P/r3-clicks.swift
xcrun swiftc -O -target arm64-apple-macos26.0 -o $W/r3-camera-list $P/r3-camera-list.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $P/r3-camera-info.plist
xcrun swiftc -O -target arm64-apple-macos26.0 -o $W/r3-bubble-camera $P/r3-bubble-camera.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $P/r3-camera-info.plist
```
The probes that record need Screen Recording for the shell you run them from, and the camera probes need the
camera for it.

The log:
```bash
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
Call it "the log line" below. The R3 lines are `Recording: filming <n> own windows (<bubble, highlights>)`,
`Recording: camera <name>, <w>×<h> at <fps> fps, started in <ms> ms`, `Recording: webcam bubble on|off at
<m:ss>`, `Recording: click highlights on|off at <m:ss>`, `Recording: bubble size <small|medium|large>`,
`Recording: camera lost at <m:ss>: <notification>`, `Recording: camera back at <m:ss>`, `Recording: camera could
not be started: <reason>`, `Recording: <bubble|highlights> window not in shareable content, not filmed`, and the
prompt lines (`Recording: <microphone|camera> access allowed|refused at the prompt`, `… at the Settings
prompt`, `Recording: camera prompt from Settings deferred, a capture is running`). No line holds a position, a
click count or a frame; check that on every log you read.

The files:
```bash
codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app
/usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" .build-rel/Build/Products/Release/TidyShot.app/Contents/Info.plist
defaults read io.tky.tidyshot recordingBubbleSize   # one key per call
```
Reading a recording's frame at a time: `ffmpeg -ss <s> -i <file>.mp4 -frames:v 1 frame.png`.

## Settings and strings
- [ ] Settings > Capture > Recording lists, in order, after `Count down before recording`: `Highlight clicks`,
  `Show webcam bubble`, `Camera`, `Bubble size` (`Small`, `Medium`, `Large`), and under the last rows `Click
  highlights and the webcam bubble apply to area and fullscreen recordings.` Both toggles are off, `Camera`
  reads `System Default` and `Bubble size` reads `Medium`. With `Show webcam bubble` off, `Camera` and `Bubble
  size` are greyed out; with it on they are live. The caption shows with either toggle on and not with both off.
- [ ] With `Format` GIF and the bubble on, `A webcam bubble makes GIFs larger, because its picture changes in
  every frame.` sits directly under `Bubble size`. With `Format` MP4 or the bubble off it is gone.
- [ ] Persistence. After the reset, `defaults read io.tky.tidyshot recordingWebcamBubble` prints `does not
  exist` (the keys are registered, not written). Turn both toggles on, choose Large, quit and reopen: the rows
  still show them, and `defaults read` (one key per call) reads `1`, `1` and `large` for
  `recordingClickHighlights`, `recordingWebcamBubble` and `recordingBubbleSize`. Hand-written bad values fall
  back: quit, `defaults write io.tky.tidyshot recordingBubbleSize -string huge`, `defaults write io.tky.tidyshot
  recordingBubbleInsetRight -float -4` and `defaults write io.tky.tidyshot recordingBubbleInsetBottom -string
  nope`, open it: `Bubble size` shows `Medium`, and the next bubble sits 16 pt from the right and bottom
  edges. Put them back with the reset loop.
- [ ] `Camera` lists `System Default` and each camera by name, and no Desk View camera (Tim's: Brio 500, TKY
  Camera, MacBook Pro Camera, LG UltraFine Display Camera, OBS Virtual Camera; the two Desk View cameras are
  not listed). With the Recording tab open, plug the Brio in: it appears; unplug it: it goes. Choose it, then
  unplug it: the row reads `Brio 500 (not connected)` and stays selected; plug it in again and the plain name
  returns. With it chosen and unplugged, quit TidyShot, `defaults delete io.tky.tidyshot recordingCameraName`,
  open it: `Unknown camera (not connected)`. Plug it in and the plain name returns. Write down what the list
  showed: ______
- [ ] `defaults read io.tky.tidyshot recordingCamera` is `default` for System Default and the camera's id for a
  pick, and `recordingCameraName` its name.
- [ ] The entitlements and the keys. `codesign -d --entitlements -` on the Release build lists R2's entitlements
  (`app-sandbox`, `device.audio-input`, `files.bookmarks.app-scope`, `files.user-selected.read-write`,
  `network.client`, the mach-lookup exception) plus `com.apple.security.device.camera` and nothing else new.
  PlistBuddy prints `TidyShot shows your camera in a bubble in screen recordings when you turn it on.` for
  `NSCameraUsageDescription`, `true` for `NSCameraUseContinuityCameraDeviceType` and `false` for
  `NSCameraReactionEffectGesturesEnabledDefault`.
  `strings .build-rel/Build/Products/Release/TidyShot.app/Contents/MacOS/TidyShot | grep -c ClickMonitorSpike`
  prints 0. Write down the output: ______

## The camera prompt (C3)
Run `tccutil reset Camera io.tky.tidyshot` first (Tim's step), then open the Release build.
- [ ] **C3.** Turn `Show webcam bubble` on in Settings with nothing recording. The system prompt appears, names
  TidyShot and shows the usage sentence. The toggle stays on whatever you answer. The log has `Recording:
  camera access allowed at the Settings prompt` or `… refused at the Settings prompt`. While the prompt is up,
  each capture shortcut does nothing, no selection overlay shows, the status menu's capture items are shown
  disabled, and `open "tidyshot://capture-area"` (URL commands on) does nothing and logs `URL command from …
  dropped, the camera prompt is open: tidyshot://capture-area`. Write down what the prompt looked like: ______
- [ ] Reset again (`tccutil reset Camera io.tky.tidyshot`), turn the bubble toggle off and then on during a
  recording. No prompt shows in the recording; the log has `Recording: camera prompt from Settings deferred, a
  capture is running`. Stop. The next start asks: Record Screen shows the prompt before the selection, and
  Record Fullscreen before the count-in. No prompt, banner or dimming is in any video. With the microphone
  also due (reset both, with a microphone chosen) the microphone prompt comes first, then the camera's.
- [ ] Deny at the start's prompt. The toggle stays on, the recording is made without the bubble, and `Recorded
  without the webcam bubble` / `Camera access is off for TidyShot.` posts only after Stop, after the save's own
  notification. Settings shows `Camera access is off for TidyShot.` with `Privacy Settings…`, which opens the
  Camera pane; turn access on in System Settings and come back: the note clears when the window becomes key.
- [ ] A GIF start still asks for the camera and not the microphone (the bubble applies to GIF).
- [ ] With the camera prompt up: a second Record press does nothing and logs `Recording: start ignored, the
  camera prompt is open`. A start refused by the lock after its prompt cannot be forced by hand (`ShortcutsTests`
  pin its notice and rule).
- [ ] Record Screen asks before its selection, so choosing a window after a camera prompt records a window with
  no bubble and no note (design, call 24). Write down what happened: ______
- [ ] With `Show webcam bubble` off, a start never prompts for the camera, whatever the access.
- [ ] The microphone pick during a recording behaves as the bubble toggle does: no prompt, `Recording:
  microphone prompt from Settings deferred, a capture is running` in the log.

## Probes left open
Each gives its command, a blank for the result and the log line. Copy the results into the R3 design's Probes.

**P1 on two displays (the 5K display and the MacBook's).** Only the LG UltraFine was attached on 2026-10-27.
```bash
$W/r3-clicks monitor 60
```
Click and right-click on each display, and across them in a drag. Do `cocoa`, `cg` and `cgEvent` agree on
both? Is a click on the second display's menu bar seen? ______

**P2, `showMouseClicks` (informational).**
```bash
$W/r3-clicks builtin /tmp/r3-builtin.mp4 12
$W/r3-clicks window <id>        # <id> is a window number the probe prints
```
Does the system's own circle (a) tell a right click from a left, (b) hold through a drag, (c) toggle through
`updateConfiguration` with an `SCRecordingOutput` attached, (d) show in a window recording? If all four are yes
the result goes to Tim, because it reopens the design's call 2. Write down each: ______ / ______ / ______ /
______ What Tim said: ______

**C2 loss steps (G4).** The runs of 2026-10-27 printed no loss notification, so the unplug, lock and take-away
steps were not done or did not interrupt the session. Do them with the probe printing:
```bash
$W/r3-bubble-camera brio 720 120
$W/r3-bubble-camera "TKY Camera" 720 120
```
During the Brio run unplug the Brio for 10 s and plug it in. During the iPhone run lock the iPhone, wait 10
s, unlock it, then take it out of range. Open the camera in Photo Booth (another app) while it runs and quit
Photo Booth. Which notifications printed, in what order, and did the picture come back on its own? Brio
unplug: ______ iPhone lock: ______ Out of range: ______ Another app: ______

**Lip sync.** See the Budget section below; its clap check is the measurement.

## Camera loss (G4), in the app
`Show webcam bubble` on, the Brio chosen, Record Fullscreen. The log line names each step.
- [ ] Unplug the Brio mid-recording, wait 10 s, plug it in. The bubble keeps its place and shows the grey circle
  with the crossed-out camera (`video.slash`, white, 40 % of the diameter), then the picture returns. The log
  has `Recording: camera lost at <m:ss>: <notification>` and `Recording: camera back at <m:ss>`. The recording
  goes on and is intact. After Stop, `Camera lost` / `The camera stopped at <m:ss>. It came back at <m:ss>.`
  posts after the save's own notification. Write down the notification's name and whether it came back by
  itself: ______
- [ ] Unplug it and leave it unplugged to Stop: `Camera lost` / `The camera stopped at <m:ss>. The bubble had no
  picture from there.` The picture was the loss picture from the unplug to the end.
- [ ] The iPhone as the camera (`TKY Camera`): lock it mid-recording, wait 10 s, unlock it. The same, with the
  loss and the return in the log. Write down what it did: ______
- [ ] Another app takes the camera (Photo Booth) and lets it go. What the bubble did, and what the log and the
  note said: ______
- [ ] Only one camera note posts per recording: with `Recorded with <name>` already posted at the start (the
  chosen camera unplugged before Record), a loss later posts nothing more.
- [ ] Turn camera access off in System Settings during a recording (Tim's step). It behaves as a loss
  (the design's rule); write down what the system did to the session and what posted: ______
- [ ] The bubble turned off from the bar logs no loss and posts no note, and its indicator light goes off at
  once. Turn it on again: the picture returns and no loss shows.
- [ ] A quick Stop and a quick bar-off while the iPhone's camera is still starting: the camera's light (and
  the menu bar's camera indicator) goes off afterwards.

## The bubble
`Show webcam bubble` on, Camera = Brio 500 unless a step says otherwise, Record Fullscreen on the display you
are on, `Count down before recording` on. The bubble is a round window that the recording films.
- [ ] No bubble shows during the area selection (Record Screen, before the rect is drawn). The bubble appears
  with the count-in, 16 pt from the area's (or the display's visible frame's) right and bottom edges, with its
  picture starting (grey, then the camera). During the count-in drag it somewhere; the log shows no
  position. The count-in's digits are over it.
- [ ] The bubble at each size: 120, 180 and 260 pt across for Small, Medium and Large (measure on a
  screenshot, ⌘⇧4). It is mirrored (raise your right hand: the bubble's left side), has a white border at
  85 % opacity inside the circle's edge, and no shadow and no name tag. The picture fills the circle with no
  stretch.
- [ ] The bubble is in the video where it was, at the size it had, mirrored, with its border and no dark halo.
  Move it during the recording and play the file: it moves in the video too.
- [ ] Double-click the bubble during the recording: Small, Medium, Large, Small, keeping its centre; a step
  against an edge clamps and stays inside the area. `Recording: bubble size <size>` is logged each time.
  `defaults read io.tky.tidyshot recordingBubbleSize` reads the last size after Stop; the next recording starts
  at it.
- [ ] Dragging, with another app frontmost (TidyShot is not active, so the first click must not be swallowed):
  the first click-and-drag moves the bubble at once, with no first click wasted. In fullscreen it cannot leave
  the display's visible frame, and so cannot cover the menu bar or the Dock; in an area it cannot leave the
  area. Drag it hard against each of the four edges, and against the Dock's edge in fullscreen with the Dock
  showing. A right-click on it does nothing.
- [ ] The transparent corners: the bubble's four square corners pass clicks through to the window under them
  (click the corner over a button in another app). A click inside the circle does not.
- [ ] Remembered place. Drag the bubble to the top-left, Stop. `defaults read io.tky.tidyshot
  recordingBubbleInsetRight` and `recordingBubbleInsetBottom` read the offsets from the right and bottom
  edges. Start another recording: the bubble starts there, whatever the area. A double-click step alone does
  not write the insets (read them before and after one). Record on the other display: the bubble sits at the
  same offsets from that display's right and bottom edges. A smaller area at the next start clamps the bubble
  inside it without changing the stored insets. Write down what you saw: ______
- [ ] Over a fullscreen Space: start the recording from a fullscreen app's Space (a fullscreen Safari). The
  bubble shows over it and is filmed.
- [ ] Under the bar: drag the bubble over the bar, double-click it, click it. The bar stays above it after each,
  and the bar is not in the file.
- [ ] A click on the bubble with highlights on draws its ring in place (see Click highlights).
- [ ] The iPhone as the camera: the same picture checks. Write down the first-picture delay after the count-in
  starts and after a count-in-off start: ______ / ______ (the design allows seconds for the iPhone; the probe
  measured 42 ms to start).
- [ ] With the count-in off, the bubble may show its grey circle for the recording's first moments, longer for
  the iPhone; the recording is not delayed.
- [ ] `Recording: camera <name>, 1280×720 at 30 fps, started in <ms> ms` is logged at the start, for the Brio and
  the iPhone. Write down both: ______ / ______
- [ ] `Recording: filming 2 own windows (bubble, highlights)` is logged at the start of every area and fullscreen
  recording, whatever the toggles say (a feature that is off has an invisible, click-through window). Write
  down the line for a recording with both toggles off: ______
- [ ] A recording with both toggles off shows no bubble, no ring and nothing from R3 anywhere, and the bar
  still has the two buttons (the next section).

## Every give-up exit with the bubble on
Each leaves no bubble on screen and the camera's light off (look at the menu bar's camera indicator and the
Brio's light). Check the log has no `camera lost` line for any of them.
- [ ] Cancel in the count-in with Escape.
- [ ] The record shortcut pressed in the count-in.
- [ ] Quit from the menu in the count-in. TidyShot quits at once with no bubble left.
- [ ] A display unplugged (or the cable pulled) in the count-in.
- [ ] A failed content read: not forceable by hand; the code path is the `defer` that every exit shares. Skip
  and write `skipped`: ______
- [ ] Stop and Cancel mid-recording: the bubble goes with the bar, and no ring or bubble is left after Stop.
- [ ] Quit with the bubble on, mid-recording: the recording is kept, no bubble is left and the camera's light is off.
- [ ] `kill -9` (`pkill -9 -x TidyShot`) with the bubble on, then relaunch: the camera's light is off, the
  recording is recovered (`Recovered a recording`), and the recovered MP4 holds what was filmed, bubble included.
  No R3 file is in `tmp` (`ls ~/Library/Containers/io.tky.tidyshot/Data/tmp`).

## Click highlights
`Highlight clicks` on, the bubble off, Record Fullscreen. Click on other apps; TidyShot is not frontmost.
- [ ] A left click draws a yellow ring (sRGB 1.0, 0.8, 0.0) 40 pt across at the click, with a dark edge and a faint
  fill; it grows from half size in 0.15 s, then expands and fades over 0.35 s, and is gone after half a
  second. Film it and step the frames (`ffmpeg` frame grabs at 30 fps): about 15 frames. Write down the
  count for a quick click: ______
- [ ] A right click draws a blue ring (0.04, 0.52, 1.0). A control-click draws the blue ring too.
- [ ] Left and right down together give two rings, each with its own life.
- [ ] A drag keeps its ring on the pointer from the down to the release, following it with no trailing, then
  fades. A double-click gives two rings.
- [ ] Rings draw over a menu, the menu bar, the Dock and a fullscreen app, and on both displays' clicks only
  inside the recorded rect: an area recording draws nothing for a click outside the area, and a fullscreen
  recording of one display draws nothing for a click on the other.
- [ ] A drag out of an area recording and released outside it: the ring waits at the nearest edge point while the
  pointer is outside, follows again if it comes back, and ends at the release wherever it lands, on the other
  display too.
- [ ] A click on the bubble (bubble on) draws its ring in place; a click on the recording bar draws none.
- [ ] No ring during the selection or the count-in, and none after Stop (click right after Stop).
- [ ] Highlights off from the bar while a button is held: that ring fades at once as if the button had come up,
  and no later click draws. A ring already fading finishes.
- [ ] Turn highlights on from the bar mid-recording: later clicks draw. The log has `Recording: click
  highlights on at <m:ss>`. In the recording's first second, a press applies from the first frame.
- [ ] No Accessibility or Input Monitoring prompt shows at any time (the monitor is a plain global monitor;
  the design's G1 rule). After `tccutil reset Accessibility io.tky.tidyshot` (Tim's step) the clicks still
  draw. Write down whether any prompt appeared: ______
- [ ] A click on a TidyShot window other than the bubble and the bar (Settings, a card) draws nothing: those windows are not in the recording anyway.
- [ ] The overlay is click-through: a click on a link under a ring works at once. It does not dim or tint the
  screen, and nothing shows in the screen at all with highlights off.
- [ ] P3's frame counts, on a recording by TidyShot. See the GIF section.

## The bar's two buttons
- [ ] An area or fullscreen MP4 with no sound has a 244 x 44 pt bar: the time, `cursorarrow` (highlights),
  `video.slash.fill` (bubble), Stop, Cancel. With sound (system audio on, or a microphone) or for a GIF it is
  280 x 44. A GIF bar has the `GIF` tag first. `9:59:59` fits every bar (the layout tests check it).
- [ ] A window recording's bar is 172 or 208 pt with neither R3 button.
- [ ] With the toggles on, the symbols read `cursorarrow.rays` and `video.fill`; off, `cursorarrow` and
  `video.slash.fill`. Tool tips (another app frontmost, hover): `Stop highlighting clicks` / `Highlight
  clicks`, `Hide the webcam bubble` / `Show the webcam bubble`. VoiceOver labels are the same for highlights and
  `Hide webcam bubble` / `Show webcam bubble`. Neither tip is in the video.
- [ ] Press each on and off mid-recording, in the first second and while the recording is ending (after Stop is
  pressed, both buttons are disabled). A bar press does not change Settings (`defaults read` before and after).
  The bubble's press applies at once, including before the first frame; the highlights press before the first
  frame applies at the first frame. The log has `Recording: webcam bubble on|off at <m:ss>` and `Recording:
  click highlights on|off at <m:ss>`.
- [ ] Bubble off then on from the bar: the bubble returns at its remembered place and size with its picture.
- [ ] A start with the bubble toggle on and no camera (everything unplugged is hard; use access denied): the
  bubble button shows `video.slash.fill`, is disabled, and its tool tip is `Camera access is off for
  TidyShot.` or `No camera is connected.`. With access never asked (after `tccutil reset Camera`), the tool tip
  is `Turn on Show webcam bubble in Settings to allow the camera.` With the toggle off and access allowed, the
  button works and turns the bubble on from the bar.
- [ ] With the bubble toggle off at the start and the bar pressed on, then Stop: a note posts only if something
  went wrong. With the toggle off and the bar never pressed, no camera note posts, whatever the access.
- [ ] A lookup miss (`Not available for this recording`, `Recorded without click highlights` / `The click
  highlights could not be filmed.`) cannot be forced by hand; the controller's tests pin it. Skip and write
  `skipped`: ______

## Window recordings
- [ ] Record Screen and click a window, with both toggles on. The recording shows that window only, with no
  bubble and no ring. The bar is 172 or 208 pt with no R3 button. The camera's light is not on (the camera
  is not opened). After the camera prompt (reset first) the recording still goes; no camera note posts. The
  log has no `filming` line. Write down what you saw: ______

## GIF
`Format` GIF, the defaults (15 fps, 1280 px), highlights and the bubble on, 60 s of steady clicking about
every 5 s with a few drags and right-clicks.
- [ ] A 15 fps GIF: every click shows in its colour (yellow, blue), the 40 pt ring reads at 0.5 px per point (20
  px across), and a quick click shows in about 7 frames. The probe's ring faded faster than the app's, so this
  is the first check of the design's 0.5 s. Write down the frames and the file size: ______ frames, ______ MB
- [ ] A 10 fps GIF: a quick click in about 5 frames, rings keep their colour. ______ frames
- [ ] With only the bubble on, the face shows (posterised, as R2 said of photos), the GIF is larger than one
  without the bubble, and merges no frames. Write down the sizes with and without: ______ / ______ MB
- [ ] With highlights off the palette is R2's: `GIFMakerTests` pin it; no step.
- [ ] A GIF of a still screen with the bubble off is small as in R2 (the regression below).

## Notes after Stop
Each posts after the save's own notification and after `Recording stopped` and the microphone note, never
during the count-in or the recording, and nothing in quit mode.
- [ ] The chosen camera unplugged before Record, another camera present: `Recorded with <default name>` / `<name>
  is not connected.` With no camera at all: `Recorded without the webcam bubble` / `No camera is connected.`
- [ ] Camera access denied: `Recorded without the webcam bubble` / `Camera access is off for TidyShot.`
- [ ] The camera lost mid-recording: `Camera lost` (the Camera loss section).
- [ ] A start with the toggle on and a camera that cannot start (not forceable by hand): `Recorded without the
  webcam bubble` / `The camera could not be started.` Skip and write `skipped`: ______
- [ ] A note and a microphone note together: the order is the save's notification, `Recording stopped`, the
  microphone note, the camera note, then the highlights note. Write down the order you saw: ______
- [ ] No camera note posts when the bubble toggle was off and the bar never pressed.

## Budget (G5)
The bubble at Medium, a 720p30 camera, one minute of Record Fullscreen with steady clicking about once a
second and highlights on. Open Activity Monitor, CPU tab, find TidyShot, and sample before and during.
```bash
footprint TidyShot | head -12        # idle, before starting
footprint TidyShot | head -12        # during the minute, with the bubble showing
```
- [ ] TidyShot's CPU with the bubble showing at Medium, Brio: ______ % (budget under 5 % of one core). iPhone:
  ______ % (the probe saw 3.3 to 5.4 %).
- [ ] CPU with highlights on and steady clicking, bubble off: ______ % (budget under 1 %).
- [ ] Memory added while the bubble shows: ______ MB (budget under 60 MB). Added by the rings: ______ MB
  (under 5 MB). The footprint before and during: ______ / ______ MB.
- [ ] A number over budget goes to Tim; the sizes and the format do not change.

## Lip sync with a clap
Brio as the camera, the RODE AI-1 as the microphone, the bubble at Medium. Face the camera and clap three times
at about 1, 2 and 3 s after the recording starts, the hands in view of the bubble. Stop. Then the iPhone as
the camera with the RODE microphone.
```bash
K0=1 python3 $P/mute-offset-onsets.py <file>.mp4    # the sound's onset for each clap
ffmpeg -ss <s> -i <file>.mp4 -frames:v 1 frame.png   # the frame where the hands meet
```
- [ ] The offset between the frame where the hands meet and the sound's onset, Brio: ______ ms. iPhone: ______
  ms. The design expects the iPhone about 40 ms behind the voice, about one frame at 30 fps, and adds no
  correction. A larger offset goes to Tim.

## Quit and sleep
- [ ] Quit with the bubble on, mid-recording (covered above): no bubble, light off.
- [ ] Sleep the Mac mid-recording with the bubble on: the recording stops and saves as in R1, and the camera's
  light is off on wake.

## The seventeen gaps, to confirm or overrule
The plan filled these where the design was silent; each was built as written (the built notes say how). Write
`confirm` or `overrule` and why, then copy the result to the design's built notes.
- [ ] 1. The camera resolve takes no toggle and runs at every start, so the bar can turn the bubble on; the note
  posts only when the bubble was wanted. ______
- [ ] 2. A window recording drops the camera and its note at the hand-off. ______
- [ ] 3. One R3 snapshot per recording: the bubble reads its toggles at the count-in, and the hand-off copies
  them, so Settings changes during the count-in do not reach the run. Check: change `Bubble size` in Settings
  during a recording: it does not apply until the next. ______
- [ ] 4. The filmed features are `bubble` and `highlights`, and a missing window disables its button. Internal. ______
- [ ] 5. The controller makes the monitors a first-frame rule (`monitoring`). Internal. ______
- [ ] 6. The notes read the controller's summary after the recording ends. Internal. ______
- [ ] 7. The recording's clock times the camera's log lines and the loss note. ______
- [ ] 8. A Settings prompt (the camera's, and now the microphone's) is deferred while a capture or a recording runs,
  and blocks captures while open. ______
- [ ] 9. The prompts' order and log lines are as the Camera prompt section says. ______
- [ ] 10. A local mouse-down draws only on the bubble; local drags and ups pass from any TidyShot window. ______
- [ ] 11. A second down for a held button ends that ring first. ______
- [ ] 12. `System Default` is the system's preferred camera when it is one of the three listed types, else the
  first listed camera. On Tim's Mac this is the iPhone (`TKY Camera`), so the Brio has to be chosen. ______
- [ ] 13. The recorded rects come from one pure function. Internal. ______
- [ ] 14. Only a drag's end writes the bubble's place; a size step writes only the size (Tim's ruling,
  2026-10-27). ______
- [ ] 15. With no 720p preset the session uses the format closest to 1280 x 720 that reaches 30 fps. Internal. ______
- [ ] 16. The ring's colours live in `ClickRingColour`, with the reserved GIF colours. Internal. ______
- [ ] 17. The click spike is Debug only and compiled out of Release. Check: the `strings` step above prints 0. ______

Calls the build made that the design did not settle (each easy to overrule):
- [ ] A. A bar-disabled bubble button keeps its own tool tip when its window is also missing (Task 9). ______
- [ ] B. The preview layer exists whenever the camera is usable, so a mid-recording press can turn the bubble
  on (Task 12). ______
- [ ] C. A camera that starts again after a loss counts as the camera's return (Task 12). ______
- [ ] D. `Recording: camera could not be started: <reason>` is logged, a line the design's list does not have
  (Task 12). ______
- [ ] E. A failed start counts as a loss in the run state, so a later reconnect shows the picture again
  (Task 11). ______
- [ ] F. The ring's grow eases out and its fade is linear (Task 10). ______
- [ ] G. After a loss the preview is hidden and the symbol shows on the grey (Task 11). ______

The design's 27 calls (Tim's to overrule) are listed at the end of the R3 design; overrule one there.

## Regression
- [ ] ⌃⇧1 to ⌃⇧7 and the R1 checklist's 6a, 6b and 7b checks behave as before after an R3 recording.
- [ ] An MP4 recording with the defaults (both toggles off) is what R2 made: `Recording saved`, the file in the
  save folder, a bar with the two R3 buttons off (244 pt, or 280 pt with sound), no camera opened (the camera
  indicator never shows), no ring, no bubble, and nothing from R3 in the video.
- [ ] A GIF with both toggles off converts as in R2 (the same palette, the same size within noise).
- [ ] The microphone prompt, mute, the microphone note and the captures-blocked rule still behave as in the R2
  checklist after the `askingPermission` rename.
- [ ] Settings > Capture > Recording's R2 rows are unchanged and the new rows sit after `Count down before
  recording`.
- [ ] Quit TidyShot with nothing recording: it quits at once.

## Observations
Write these into the R3 design's Probes section and built notes:
- P1 on the 5K display and a second display; P2's four answers and what Tim said.
- C3: what the first camera prompt looked like and what each answer did.
- Which notifications a lost camera posted (the Brio unplug, the iPhone lock, another app), and whether the
  session came back by itself (G4); the note's wording if it needs to change.
- TidyShot's CPU, the footprint before and during, for the Brio and the iPhone (G5).
- The lip-sync offsets for the Brio and the iPhone.
- The GIF frame counts for a quick click at 15 and 10 fps, and the GIF sizes with and without the bubble.
- The first-picture delay for the iPhone.
- Anything above that failed, and each gap and call confirmed or overruled.
