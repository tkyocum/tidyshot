# Recording R2 manual test checklist

Run after any change to `TidyShot/Recording/` (`GIF/`, `GIFMaker`, `GIFConversion`, `RecordingMute`,
`MuteLog`, `MuteLogWriter`, `MicrophoneChoice`, `MicrophoneDevices`, `MicrophoneLatency`,
`RecordingTrim`, the controller, the chrome and the panel), `AppCoordinator` (`+Recording`'s
`makeGIF`, `muteAndSave`, `recoverRecordings` and `saveRecording`, `+Upload`'s `startUpload`, `retry`
and the `uploadRefusal` gates, `+RecordActions`, `+DragOut`, `+Delete`, `+Overlay`, `+Trim`),
`StatusMenuController`, the Recording section of Settings > Capture, the card, Recent Captures,
`ThumbnailProvider`, or the `Recording`, `MuteLog` and `CaptureRecord` fields. Automated tests cover the
pure decisions (the GIF palette, differ, LZW writer, sink and encoder against ImageIO's decoder, the
conversion steps and their one `saveRecording` call, the progress menu, the settings layout, the
panel's three bars, the microphone choice, the lag, the mute segments and `apply` on tone fixtures,
the ladder with injected steps, the mute log's writer, recovery's rules, the save plan for a marked
recording, the refusals for a marked or trimming record, Trim's range, source, sheet and write plans,
and the card, row and menu rules for a GIF, a stale link and a marked record). Everything here needs a
real screen, Screen Recording, a microphone, real windows, a player, the network, Clop or eyes. The
R1 checklist (`recording-r1-manual-checklist.md`) still covers starting, stopping, sleep, quitting and
the upload paths for an MP4; run it too after a change to those.

Several steps are probes: they run a small program next to the app, or read the app's log, and ask
you to write down what the system did. Those results settle the R2 design's "Still to probe" list and
the twelve gaps at the end. Fill each blank, then copy the results into the design's Probes section
(`docs/superpowers/specs/2026-10-23-tidyshot-screen-recording-r2-design.md`) and mark the item done in
its R2 built notes.

## Held gates (read this first)

R2 was built with these steps held, as the plan's Gates section says. The branch is not offered for
merge while one is held. Each needs Tim; none could run unattended, because the Debug build has no
Screen Recording grant and a grant is Tim's to give.

- **H1. The microphone's start (Task 4's sandboxed-capture gate).** Held: "Wire the start" (the
  permission prompt before the capture lock, `isAskingMicrophone`, `MicrophoneChoice.resolve` under the
  lock, the `Resolution` carried into `RecordingOptions.microphoneID`), "Post the note last"
  (`saveRecording(… microphoneNote:)`) and the microphone hand checks. Until it lands no recording
  captures the microphone, the mute lag is always the no-microphone 0.3 s, and Settings > Capture >
  Recording > `Microphone` stores a choice that nothing reads at the start. What Tim does: the
  sandboxed `RecordingSpike` run in Probe 4 below, then write the result into the design's Probes.
  If the sandboxed capture differs from the unsandboxed probes (no prompt, no `soun` track, an
  error), the held steps wait for a design amendment.
- **H2. Trim's re-encode (Task 7's trim gate, tripped).** Held: `RecordingTrim.startsOnSyncSample`,
  `export` and `exportForSave` with their tests, `TrimWindowController`, `trimWindows`, the pass, the
  put, the download and the clean-up in `AppCoordinator+Trim.swift` (`trimCapture`, `uploadTrimmed`,
  `finishTrimWrite`), closing a Trim window in `removeRecord` and `removeFiles(ofPruned:)`, and the
  card's and row's wiring (`trimState` stays at its default, so `Trim…` and `Upload Trimmed` are
  hidden, and the closures are no-ops). The probe showed `HighestQuality` passes H.264 at or under
  3840×2160 through (its progress does not move and the cut samples stay in the file), scales larger
  recordings down to 3840×2160, and one re-encode came out larger than its source. The design needs an
  amendment before the export is built; what it has to settle is under Trim in the R2 built notes.
  What Tim does: decide the four points there, and run Probe 5 on his own 60 s recordings. Every Trim
  section of this checklist waits for it.
- **H3. The input-latency measurements (Task 6).** Holds no code: the design's constants stay, and an
  input whose measured offset falls outside its lag goes back to Tim and into the PR. What Tim does:
  Probe 6 below with AirPods, the Brio 500, the iPhone input and a USB input.
- **H4. The GIF encoder probe (Task 3).** Holds nothing: a result Tim finds poor goes to him (the
  selective ordered dither), and the defaults stay. What Tim does: Probe 1 (browsers) and Probe 2
  (content the spike's three inputs did not cover). A synthetic diagonal gradient already showed
  stair-step bands (30 colours across a 1280 px row, runs of up to 95 px, MAE 0.91), so look at a
  real wallpaper gradient first.
- **H5. Hand checks no one has run.** Tasks 3, 6 and 8 each left their hand checks (a GIF recording,
  the mute button, a GIF's card and row) because the Debug build had no grant. They are the GIF,
  Settings and Mute sections below. The Microphone and Trim sections wait for H1 and H2.

Sections marked **(held: H1)** or **(held: H2)** can only run once that step has landed. Run
everything else now.

## Setup

A fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted to that build
(it is signed ad hoc, so every rebuild needs a new grant; see `Config/Local.xcconfig`), "Show
notification" and "Play sound" on in Settings > General, Allow URL commands on, an upload destination
that works, and Clop (direct or Setapp) installed and running. Steps marked **(Debug)** need the Debug
build, because `-MuteFailure` and `-RecordingSpike` are compiled out of Release; build it with
`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build
build` and give `.build/Build/Products/Debug/TidyShot.app` its own Screen Recording grant (and its own
microphone prompt). Only one TidyShot may run at a time. You also need a Retina display, the 5K display
for the large-output step, a save folder on a volume other than the startup volume (the disk image below),
the microphone inputs named under H3, and Safari, Chrome, Firefox, QuickTime Player, IINA or VLC, Slack and
a GitHub comment box. Quit TidyShot, start from the defaults, then open it again:
```bash
for k in recordingFormat gifFrameRate gifMaxSide recordingMicrophone recordingMicrophoneName \
         recordingFrameRate recordingRetina recordingSystemAudio recordingShowsCursor recordingCountdown \
         recordingFileNameTemplate; do
  defaults delete io.tky.tidyshot $k
done
```
A key that was never set prints `does not exist`, which is fine. `afterCaptureAction` and
`optimiseWithClop` are set by the steps that need them; put them back at the end.

Make the working folder, the probes and a disk image once.
```bash
mkdir -p ~/Desktop/rec-r2 && cd ~/Desktop/rec-r2
W=~/Desktop/rec-r2
P=~/git/tidyshot/docs/superpowers/research/recording-probes
xcrun swiftc -O -target arm64-apple-macos26.0 -o $W/audio-devices $P/audio-devices.swift
xcrun swiftc -O -target arm64-apple-macos26.0 -o $W/trim-reencode $P/trim-reencode.swift
mkdir -p $W/mic && cp $P/mute-offset-mic.swift $W/mic/main.swift
xcrun swiftc -O -target arm64-apple-macos26.0 -o $W/mute-offset-mic $W/mic/main.swift \
  ~/git/tidyshot/TidyShot/Recording/MicrophoneLatency.swift
mkdir -p $W/spike
xcrun swiftc -O -swift-version 6 -default-isolation MainActor -o $W/spike/gifspike $P/gif-encoder-spike/gifspike.swift
hdiutil create -size 4g -type SPARSE -fs APFS -volname RecOff off && hdiutil attach off.sparseimage
```
`/Volumes/RecOff` is the save folder off the startup volume. Detach it at the end: `hdiutil detach
/Volumes/RecOff`. The probes that record need Screen Recording (and Microphone for `mute-offset-mic`) for
the shell you run them from.

The files and the log:
```bash
C=~/Library/Containers/io.tky.tidyshot/Data
ls $C/tmp/Recording $C/tmp/Mute $C/tmp/Trim $C/tmp/Clop $C/tmp/Drag "$C/Library/Application Support/TidyShot/pending"
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
`tmp/Recording` holds a recording (and a GIF while it is made) until a record points at its new place;
`tmp/Mute` holds the mute logs (`<id>.json`) and a rewrite while the ladder runs; `tmp/Trim` is cleared
at launch and holds Trim's work files; `tmp/Clop`, `tmp/Drag` and `pending` are as in R1. The log
command prints the app's `Recording:` lines, among them `Recording: mute lag <s> s (<input>)` at each
start, the recovery lines, and the conversion's. Call it "the log line" below. The `Clop:` lines come
from `NSLog`, which `log show` prints as `<private>`; to read them start TidyShot with its stderr in a
file (quit it from the menu first, `open -n` starts a second copy): `open -n --stderr
~/Desktop/rec-r2/tidyshot.err ~/git/tidyshot/.build-rel/Build/Products/Release/TidyShot.app`, check
that `pgrep -x TidyShot` prints one id, and later `grep 'Clop:' ~/Desktop/rec-r2/tidyshot.err`. Add
`--args -MuteFailure both` after the app path for the Debug steps that inject a failure (`open -n
--stderr … <Debug app> --args -MuteFailure both`).

Reading a GIF: `magick identify -format '%T\n' <file>.gif | awk '{n++; s+=$1} END {print n" frames, "s" cs"}'`
prints the GIF frame count and the summed delays; `ffprobe -v error -show_entries stream=width,height
-of csv=p=0 <file>.gif` its size; `afinfo <file>.mp4` an MP4's audio track (a `Data format` line with
`aac`; an error or no such line means none). The three after-capture actions are `Save and copy image`
(`.save`), `Upload and copy URL` (`.upload`) and `Upload only, keep no local file` (`.uploadOnly`).

## Settings and strings
- [ ] Settings > Capture > Recording lists, in order: `Format` (`MP4`, `GIF`; MP4 selected), `Frame rate`
  (`30 fps`, `60 fps`), `Resolution` with `Retina is capped at 4096 px on the longer side.`, `Record
  system audio`, `Microphone` (`Off` selected), `Show cursor in recordings` and `Count down before
  recording`.
- [ ] Switch `Format` to GIF. `Frame rate` goes. `GIF frame rate` (`10 fps`, `15 fps` selected, `20 fps`)
  and `GIF size` (`800 px`, `1280 px` selected, `Full size`) appear before `Resolution`, with `Full size
  GIFs can be very large.` under them. `Record system audio` and `Microphone` are greyed, and `GIFs have
  no sound. Sound settings apply to MP4 recordings.` sits directly under `Microphone`. Switch back: the
  rows return as they were. (As built, the `Full size` caption shows whenever GIF is chosen, not only
  while `Full size` is selected; see the built notes, GIF, Settings.)
- [ ] Persistence. After the reset, `defaults read io.tky.tidyshot recordingFormat` prints `does not
  exist`: the five defaults are registered, not written. Change `Format` to GIF, `GIF frame rate` to
  20 fps and `GIF size` to `Full size`, quit and reopen: the panes still show them, and `defaults read
  io.tky.tidyshot <key>` (one key per call) reads `gif`, `20` and `0` for `recordingFormat`,
  `gifFrameRate` and `gifMaxSide`. Hand-written values fall back. TidyShot reads its settings only at
  launch, so quit it first, then `defaults write io.tky.tidyshot gifFrameRate -int 12`, `defaults write
  io.tky.tidyshot gifMaxSide -int 640` and `defaults write io.tky.tidyshot recordingFormat -string webm`,
  and open it again: `Format` shows `MP4`; switch it to GIF and the rows show `15 fps` and `1280 px`.
  Quit, put them back with the reset loop, and open it again.
- [ ] `Microphone` lists `Off`, `System Default` and each input by name (Tim's six: TKY Microphone,
  Brio 500, MacBook Pro Microphone, LG UltraFine Display Audio, CalDigit TS4 Audio - Rear, RODE AI-1).
  With the Recording tab open, plug the RODE AI-1 in: it appears; unplug it: it goes. Choose it, then
  unplug it: the row reads `RODE AI-1 (not connected)` and stays selected; plug it in
  again and the plain name returns. With it chosen and unplugged, quit TidyShot, run `defaults delete
  io.tky.tidyshot recordingMicrophoneName` and open it again (it reads the name only at launch, and writes it
  back while the input is plugged in): the row reads `Unknown microphone (not connected)`. Plug it in, and the
  plain name returns.
- [ ] Choosing an input with access not yet decided shows the system prompt, which reads `TidyShot
  records your microphone in screen recordings when you turn it on.`. Allow keeps the choice. After
  `tccutil reset Microphone io.tky.tidyshot`, choosing an input and answering Don't Allow puts the row
  back on `Off`.
- [ ] With a microphone chosen and TidyShot's access turned off in System Settings > Privacy & Security >
  Microphone, the row shows `Microphone access is off for TidyShot.` with `Privacy Settings…`. The button
  opens the Microphone pane. Turn access on again and come back to Settings: the note clears when the
  window becomes key. Choosing an input while access is already denied puts the row back on `Off` and
  shows no note (a design-silent corner; write down what you think: ______).
- [ ] The entitlements and the usage string. `codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app`
  lists R1's entitlements plus `com.apple.security.device.audio-input` and nothing else new, and
  `/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" .build-rel/Build/Products/Release/TidyShot.app/Contents/Info.plist`
  prints the sentence above.

## GIF
Settings > General > After capture = `Save and copy image` unless a step says otherwise. Record with
Format = GIF. ⌃⇧8 and drag an area; the bar is for GIF.
- [ ] The bar is 208 x 44 pt with a `GIF` tag before the time and no mute button, then Stop and Cancel. The
  tag is bordered, the time counts up, and the bar is not in the file. Past 30 s the time turns orange
  (the MP4 bar turns orange at 5:00). Leave one running to `1:00:00` if you can; `RecordingPanelLayoutTests` lays
  the bar out with `9:59:59`.
- [ ] A GIF recording is made at 30 fps with no sound whatever the settings say. With `Frame rate` 60 fps and
  `Record system audio` on (set them before switching `Format` to GIF) and a sound playing, record a few
  seconds and press `Stop Making GIF` as soon as the menu shows it: the MP4 it saves has no audio track
  (`afinfo` prints no `aac` line), and the log line's `Recording: starting …` reads `30 fps` and `microphone
  off`.
- [ ] Stop after about 10 s of scrolling text (a long web page scrolled at a steady pace) at the defaults
  (15 fps, 1280 px). The status menu shows a disabled `Making GIF… <n> %` and, under it, `Stop Making GIF`
  while it converts; no card, row or `Recording saved` appears until it is done. Then one card with the
  poster, a `GIF` badge and the duration, a `.gif` file named from `Recording file name` in the save
  folder, and the clipboard rule of the after-capture action. Write down the conversion time and the size:
  ______ s, ______ MB (the spike: 3.8 s and 14.8 MB for 10.3 s of `window.mp4`).
- [ ] Sharpness. Open the GIF in Preview or Safari and zoom to 300–400 % on text: no blur, no fringing, no
  speckle on flat backgrounds; flat colours exact. Do it for `800 px`, `1280 px` and `Full size`. Sizes against
  the spike's `window` row: 7.4 MB at 800 px, 14.8 MB at 1280 px, 28.5 MB at full size (same content, same
  length). Write down what you got: ______ / ______ / ______
- [ ] Timing. `magick identify` on the 15 fps GIF gives delays of 7, 6, 7 cs, and the summed delay is
  `round(F × 100 / 15)` for its `F` output frames (155 frames is 1033 cs), so within a frame of the
  recording's length: 10 s is about 1000 cs, not the 1050 that a 7 cs delay on every frame would give. At 10
  and 20 fps the delays are 10 and 5. Write down one: ______
- [ ] Merging. Record 10 s of a mostly static screen (a clock ticking, nothing else) at the defaults. The
  GIF is far smaller than the scrolling one and has far fewer GIF frames than 150, with long delays on the
  held stretches. Write down the frames and the size: ______ frames, ______ MB (the spike's mostly static
  3 s area: 0.31 MB, smaller than its MP4).
- [ ] `Full size` on a Retina area larger than 4096 px on its long side is capped at 4096 px (R1's cap).
  Record a 2560 x 1440 pt area on the 5K display at `Full size` for 10 s: the GIF is 4096 x 2304 or smaller,
  and plays.
- [ ] Colour. Record each for 10 s at the defaults and look zoomed: (a) a photo gallery, (b) a playing video,
  (c) dark mode with a terminal and an editor, (d) a low-contrast UI (grey on grey), (e) a wallpaper gradient
  with a window dragged over it, (f) a colourful popup shown for under a second (a notification banner with
  an icon). Posterisation and banding are acceptable to Tim, or the selective ordered dither goes back to him
  (design, GIF, Encoding); the popup keeps its hue. Write down which are acceptable: ______
- [ ] Playback. Open one GIF in Safari, Chrome, Firefox, Quick Look (space bar in Finder), Slack (attach it
  to a message to yourself) and a GitHub comment box (Preview): it plays, loops, and holds its delays (it does
  not play fast or slow against the clock). Write down any that differ: ______
- [ ] Two GIF recordings converting at once. Record two 30 s GIFs back to back (Stop the second as soon as
  the first is converting). The menu shows `Making 2 GIFs… <n> %` and `Stop Making GIFs`, with `n` weighted by
  frame count. Press `Stop Making GIFs` while both run: each recording is saved as an MP4 with its own
  `GIF not made` notification (`Stopped. The recording was saved as an MP4.`), two records appear, and
  `tmp/Recording` has no `.gif` left.
- [ ] `Stop Making GIF` with one conversion does the same for that recording. Pressing it after the menu shows
  `99 %` (the GIF is written and being saved) does nothing: the GIF is saved.
- [ ] Quit during a conversion. Start a 60 s GIF's conversion and quit from the menu: TidyShot quits without
  waiting for the conversion, the recording is in the save folder (or `pending`) as an MP4 with a record, no
  notification posts, and no `.gif` is left in `tmp/Recording`.
- [ ] `kill -9` during a conversion (`pkill -9 -x TidyShot`), then relaunch: `Recovered a recording` posts for
  one MP4 recording, it plays, no record shows a GIF, and `tmp/Recording` is empty. If a GIF had been moved
  and the kill came before the MP4 was removed (a few milliseconds; probably not reproducible by hand), the
  next launch logs `Recording: <name> was saved as a GIF, removed`. Write down what happened: ______
- [ ] A nearly full disk (optional). **This fills the startup volume. With under 1 GB free, other apps, swap
  and macOS itself can fail or lose unsaved work, so save and quit what you can first, keep `rm
  ~/Desktop/fill1.bin ~/Desktop/fill2.bin` typed in a second Terminal window, and skip the step (write
  `skipped` below) if you would rather not.** The conversion needs 1 GB free where it starts, and a recording
  stops itself under 1 GB, so the two meet. Fill the startup volume with `mkfile <n>g ~/Desktop/fill1.bin`
  until `df -g /` shows about 2.2 GB free, start a GIF recording, then `mkfile 1500m ~/Desktop/fill2.bin` so
  under 1 GB is left: the recording stops itself, and the conversion does not start. `GIF not made` / `Not
  enough disk space to make the GIF. The recording was saved as an MP4.` posts, the MP4 is saved with its
  record, and no `<id>.gif` is left in `tmp/Recording`. Delete both filler files at once. (The mid-write
  check at every 32 MB cannot be forced by hand; `GIFFileSinkTests` cover it.) Write down whether you ran
  it: ______
- [ ] Conversion times. Record 30 s and 60 s at 15 fps and 1280 px of scrolling text, of a mostly static
  screen and of colour-heavy content, and 30 s at `Full size` of the colour-heavy content. Write down each
  time against the recording's length: ______ (the spike took 3.8 s for 10.3 s of text at 1280 px, 4.2 s
  for 4.2 s of colour-heavy content and 15.7 s for that at full size, so `Full size` can take longer than the
  recording).
- [ ] Memory. During a conversion run `footprint TidyShot | head -12` and read the footprint, and once
  idle. At the defaults the rise is under 100 MB, at `Full size` for a 4096 px recording under 300 MB, and it
  does not grow with length (60 s against 10 s). Write down idle and peak: ______ / ______ MB
- [ ] A GIF's card and row. The card has the poster with a `GIF` badge and the duration; its menu and the row
  show no Annotate, Pin to Screen or Copy Image; they have `Copy File` (with a local file), `Save As…`,
  `Reveal in Finder`, `Close` and `Delete…`. A thumbnail click opens the GIF in the default app and it plays.
  `Save As…` offers `com.compuserve.gif` and writes a `.gif` (over an existing file too, and on
  `/Volumes/RecOff`). A card press for a drag stages the `.gif` and downloads nothing. The hover preview in
  Recent Captures shows the stored thumbnail at its own size. Drag the card into Finder and Slack: the
  `.gif` arrives under its name.
- [ ] A GIF's upload and the clipboard. `Upload and copy URL` with Clop **off**: the URL replaces the
  clipboard only when nothing was copied in between; copy text while it uploads and the text stays,
  `Uploaded` posts, and a click copies the link. The link plays the GIF in a browser. Uploading uses the
  `image/gif` content type: `curl -sI "<url>" | grep -i content-type`.
- [ ] Clop on and running, then a GIF: it uploads as made. The card never says `Optimizing…`; the uploaded
  object is byte-identical to the saved file (`curl -s -o $W/up.gif "<url>"; cmp $W/up.gif "<saved .gif>"`);
  and `grep 'Clop: GIFs are not sent to Clop' ~/Desktop/rec-r2/tidyshot.err` finds one line, and still one
  after a second GIF upload in the same launch; after a relaunch, one more. An MP4 recording still goes through
  Clop (`Optimizing…`, a smaller object). With Clop off the GIF line is never logged.

## Mute (system audio now; the microphone is held: H1)
The button shows for `capturesAudio || captureMicrophone`. Settings > Capture > `Record system audio` on,
`Format` MP4. Play a steady sound from another app (`afplay /System/Library/Sounds/Submarine.aiff` in a
loop, or music).
- [ ] The bar is 208 x 44 pt with the time, the mute button (`speaker.wave.2.fill`), Stop and Cancel. With
  `Record system audio` off and no microphone the bar is 172 x 44 with no mute button, and the same for an
  MP4 whose only sound would have been a microphone dropped at the start. For a GIF it is the `GIF` bar
  (above).
- [ ] With another app frontmost, hover the mute button and then Cancel: the tool tips `Mute the sound` and
  `Discard the recording` show (R1's Cancel tool tip never showed before). After a press the button is
  `speaker.slash.fill` and its tip is `Unmute the sound`. Neither tip is in the video.
- [ ] Press mute at about 3 s, unmute at about 6 s, mute at about 8 s and Stop at 10 s (muted). The log line
  shows `Recording: mute lag 0.300 s (no microphone)` at the start. `tmp/Mute/<id>.json` appears at the first
  press. After Stop the file keeps its length; play it in QuickTime and in IINA or VLC (Clop off): each
  stretch is silenced from 0.1 s before the press to 0.3 s after the unmute (about 2.9 s to 6.3 s, and 7.9 s
  to the end), sound elsewhere is on time with the picture, and the audio ends with the video. `tmp/Mute` is
  empty afterwards. Write down anything off: ______
  Do it as the first muted recording after a launch, and write down the seconds from Stop to the card: ______
  s. Expect about a second: the rewrite of a 10 s recording takes a fraction of that, because `apply` decodes
  with `AVAudioConverter` and opens no audio queue. The reader's own decode waited 90 s on coreaudiod on
  Tim's Mac (built notes, The suite's time); a wait of more than a few seconds here goes to Tim.
- [ ] Press mute in the first second (the button is live as soon as the bar shows): the first stretch starts
  at 0. Press it before the first frame if you can.
- [ ] With Clop on and `Upload and copy URL`, the same recording: the uploaded link plays in Safari and in
  Chrome with the muted stretches silent and later sound in sync. (Clop took a muted fixture from 14 MB to
  4.8 MB and kept it silent in the probe.) Write down the sizes before and after: ______ MB, ______ MB
- [ ] A recording never muted leaves no log and its audio is untouched (`ls $C/tmp/Mute` is empty).
- [ ] **(Debug)** `open -n --stderr … <Debug app> --args -MuteFailure apply`, then mute a stretch and Stop:
  `Sound removed` / `Muting failed, so the recording has no sound.` posts, the file has no audio track
  (`afinfo` shows none), and the log has `Recording: mute failed: It failed on purpose (-MuteFailure).`
- [ ] **(Debug)** `--args -MuteFailure both`, for each of Save with a folder set, Save with no folder,
  Upload and Upload only: no folder panel opens, the file is in `pending/` and not in the save folder,
  nothing uploads, the clipboard is unchanged, `Sound not muted` / `Muting failed. The recording is kept in
  TidyShot and not uploaded. Trim it to fix the sound, or delete it.` posts, the card and the row read `Sound
  not muted` (the card's tooltip shows the whole sentence), Retry Failed Uploads skips it with no notice, and
  a relaunch keeps the mark. The marked card offers the thumbnail's Open and Delete (and `Trim…`, once H2
  lands), with no Copy File, Save As… or drag; the row's click opens the file. Write down what the card and
  menu offered: ______
- [ ] **(Debug)** `kill -9` during a muted recording, then relaunch with `--args -MuteFailure both`: the
  recovered record shows `Sound not muted`, and `Recovered a recording` ends `Its sound is not muted, so it
  was not uploaded.`
- [ ] `kill -9` (a) during a recording while muted, (b) just after Stop, (c) during the mute rewrite (a long
  recording makes the window longer). After each relaunch only one record appears, the muted stretch is
  silent, and `Recovered a recording` ends `The muted parts were silenced.` (and `tmp/Mute` is empty after the
  sweep). Write down which of the three left what: ______
- [ ] A mute that cannot start for want of space cannot be run by hand; `RecordingMuteTests` cover the
  `Recording: mute skipped, not enough disk space` path.
- [ ] A discarded muted recording leaves no log: mute for a second, press Cancel past 5 s and Discard;
  `ls $C/tmp/Mute $C/tmp/Recording` shows both empty.

## Microphone (held: H1)
These need the start path. Until it lands the recording does not use the microphone (see H1); do the
Settings checks above now and the rest later.
- [ ] Each input (Tim's six), access denied and allowed: the file has a stereo AAC track with the voice, mixed
  with system audio when both are on; `afinfo` shows one audio track. The log line shows the chosen input's
  `uniqueID` on the stream start.
- [ ] After a rebuild (new ad-hoc signature, so no grant) with a microphone set, for Record Screen and for
  Record Fullscreen: the system prompt appears before the selection overlay or the count-in; Allow records
  with the microphone; Deny (or `tccutil reset Microphone io.tky.tidyshot` then Deny) records without it, the
  note `Recorded without the microphone` / `Microphone access is off for TidyShot.` posts only after Stop and
  after the save's own notification, and no prompt or banner is in the video.
- [ ] With the prompt up: a second Record press does nothing and logs `Recording: start ignored, the microphone
  prompt is open`; a screenshot shortcut works; Quit quits without starting a recording.
- [ ] The chosen input unplugged before the recording (or the RODE AI-1 chosen while unplugged): the recording
  uses the default input, and `Recorded with <default input name>` / `<name> is not connected.` posts after
  Stop. With no input at all: `Recorded without the microphone` / `No microphone is connected.`
- [ ] A GIF with a microphone set never prompts and never posts a microphone note.
- [ ] Access turned off, and the input unplugged, during a recording: what ScreenCaptureKit does (the stream
  stops, the output fails, or the file goes on with silence), whether the file is saved and plays, and the
  `Recording stopped` body (`The microphone was disconnected.` or `Microphone access is off for TidyShot.`).
  Write down what happened for each: ______ / ______
- [ ] Mute on and off during a recording with the microphone and with system audio, pressed in the first
  second, and Stop while muted; with Clop on, play the uploaded link in Safari and Chrome; with Clop off, open
  the saved file in QuickTime and in VLC or IINA. The muted stretches are silent, sound after them is in sync,
  and the audio ends with the video.
- [ ] With the iPhone input (TKY Microphone), a USB input and AirPods (Bluetooth, the high-latency case): the
  logged lag (`Recording: mute lag <s> s (<name>)`), and a word started within 0.2 s of each mute and unmute
  click is silent. Write down each input's logged lag: ______ (see Probe 6)

## Trim (held: H2)
Run these once the export, the window and the wiring have landed; the amended design may change a step.
- [ ] `Trim…` shows in the card's menu and the Recent Captures row actions (`scissors`) for MP4 recordings only,
  not for a GIF; it is disabled while the record uploads or is being deleted.
- [ ] Save, Save and Upload (the link plays the trimmed video), an upload-only record that needs the download
  (the sheet offers `Save and Upload` only), and both Cancels (the bar's and the sheet's).
- [ ] A start between keyframes: `Trimming…` shows with a moving bar and `Stop`; the result plays from the
  chosen frame; IINA or `ffmpeg -ignore_editlist` shows nothing from before the start; text is as sharp as in
  the original; `Stop` writes nothing and closes the window. Write down the time of a 60 s 4K re-encode:
  ______ s
- [ ] A trim that only moves the end: saved at once, with no sheet.
- [ ] The sheet's text, buttons and default button for each row of the design's table (Save target with a
  destination and a link, with a destination and no link, with no destination; `.unavailable` with a
  destination; `.unavailable` with none disables `Trim…`). Save on an uploaded recording shows `Link not
  updated`; `Upload Trimmed` clears it; a failed Save and Upload (network off) leaves it.
- [ ] Save and Save and Upload with the record's file in a save folder on another volume (`/Volumes/RecOff`),
  in the sandboxed build, after a relaunch (the stored bookmark's scope), and with a recording in `pending/`:
  the file is replaced and plays trimmed, the duration and thumbnail update, and nothing stray is left in the
  folder or its `.TemporaryItems`. R1 did not see a replace under the sandbox; if the sandbox refuses the
  volume's replacement folder, stage a temporary file in the save folder itself under the scope and
  `replaceItemAt` from there. Write down what happened: ______
- [ ] Retry a failed upload while its Trim window is open, then Save: `Not trimmed` / `This capture is still
  uploading.`, and the uploaded object still matches the local file.
- [ ] Delete the record while its Trim window is open: the window closes, and nothing reappears in the save
  folder or `pending/`.
- [ ] During a slow Save to the other volume (a long recording): Retry, `Upload Trimmed` and Delete are
  disabled or refused with `This capture is being trimmed.` (`Not deleted` / `This capture is being trimmed.
  Delete it when the trim finishes.`), and once the put finishes the file plays trimmed and Delete works.
- [ ] Close the Trim window of an upload-only record: `tmp/Trim/<id>.mp4` is gone.
- [ ] An upload-only video whose card was dragged before the trim: after Save and Upload, drag-out and Save
  As… give the trimmed video, and `tmp/Drag/<id>` holds the trimmed file, not the old copy.
- [ ] A `Sound not muted` record: Trim then Save leaves its muted stretches silent and clears the mark; after
  that Upload works.
- [ ] A passthrough keeps at most two AAC packets (2,048 sample frames) of audio before the start; more goes
  back to Tim before the export is built (Probe 5).

## Probes left open
Each gives its command, a blank for the result and the log line. Copy the results into the R2 design's
Probes and mark the item done in its R2 built notes.

**Probe 1. The spike's GIFs in browsers (H4).** Remake them with `measure.sh` (it needs `window.mp4`,
`p-area.mp4` and `p-4096.mp4` in `$W/spike`; without them open GIFs the app made), then open each
`final/*-ours.gif` in Chrome and Firefox.
```bash
cd ~/git/tidyshot/docs/superpowers/research/recording-probes/gif-encoder-spike && ./measure.sh $W/spike
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
Do they play, loop, and hold their delays (compare the wall-clock length with `magick identify`)? Chrome:
______ Firefox: ______ (The app's GIFs are in the GIF section's Playback step.)

**Probe 2. The encoder on content the spike did not see (H4).** Record each as an MP4 (Format = MP4) for 10 s:
a dark-mode terminal and editor, a low-contrast UI, a wide-gamut or HDR source (an HDR video in QuickTime,
or Display P3 photos), and a wallpaper gradient behind a window being dragged. Then, for each file:
```bash
cd $W/spike && ./gifspike encode dark.mp4 dark.gif --minsigma 2 --keep 4 --stats && ./gifspike validate dark.gif --zoom 3 --cw 200 --ch 120
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
Write the MP4 size, the GIF size, the MAE and what the zoomed crops (`dark.gif.*.png`) show about
posterisation and banding: dark ______ low-contrast ______ wide-gamut ______ gradient ______ Anything Tim
finds poor goes back to him: the answer is the selective ordered dither, not a change to the defaults.

**Probe 3. Conversion timing and memory at length (H4).** Part of the GIF section's two steps; write the
numbers here too. Run `footprint` once idle and again while a conversion runs.
```bash
footprint TidyShot | head -12
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
30 s ______ 60 s ______ `Full size` 30 s ______ idle/peak footprint ______ / ______ MB

**Probe 4. A sandboxed `RecordingSpike` run with the microphone (H1, Debug).** Grant Screen Recording to
`.build/Build/Products/Debug/TidyShot.app` (from the last full test run; any rebuild needs a new grant), then:
```bash
open ~/git/tidyshot/.build/Build/Products/Debug/TidyShot.app --args -RecordingSpike YES -RecordingSpikeMicrophone default
sleep 12
/usr/bin/log show --last 2m --style compact --predicate 'process == "TidyShot"' | grep "Recording spike"
/usr/bin/log show --last 2m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
Answer the microphone prompt and speak during the 3 s. The prompt names TidyShot and shows the usage
sentence. The log shows the access before and after the prompt, the answer, the default input's name and
`uniqueID`, and `starting …, microphone <uniqueID>`; the file line says `soun×1`, and the recording is in
`~/Library/Containers/io.tky.tidyshot/Data/tmp/RecordingSpike/` with the speech audible. Result: prompt
______ access before/after ______ input ______ file line ______ audible ______ If the sandboxed capture differs
from the unsandboxed probes (no prompt, no `soun` track, an error), the held steps wait for a design
amendment.

**Probe 5. The trim re-encode on Tim's recordings (H2).** Make `SCRecordingOutput` recordings of 60 s at
2560×1664 and at 4096×2304 with the app (moving content, with system audio), then, with one start between
keyframes and one on a keyframe's track time (its media time minus the first edit's media start):
```bash
$W/trim-reencode ~/Movies/rec-2560.mp4 12.5 $W && $W/trim-reencode ~/Movies/rec-2560.mp4 <keyframe track time> $W
$W/trim-reencode ~/Movies/rec-4096.mp4 12.5 $W && $W/trim-reencode ~/Movies/rec-4096.mp4 <keyframe track time> $W
ffmpeg -ignore_editlist 1 -i $W/trim-hq-composed.mp4 -f null - 2>&1 | grep -i frame=
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
Write down for each size: whether `AVSampleCursor` reports the sync samples (about 2 s apart); the passthrough's,
`HighestQuality`'s and the composed re-encode's time, size and `fractionCompleted` readings; whether the
progress moves; whether the output holds a video sample before the start; the audio packets before the start
(at most 2, 2,048 sample frames); whether text is sharp in the re-encode; whether the re-encode is larger than
its source. 2560: ______ 4096: ______ (The earlier probe, on the recordings at hand, is in the design's
Probes: `HighestQuality` passed H.264 at or under 3840×2160 through.)

**Probe 6. Input latency (H3).** List the inputs, read each one's reported latency and lag without recording,
then record the offset per input:
```bash
$W/audio-devices
$W/mute-offset-mic $W/anything.mp4 "<UID>" default latency
$W/mute-offset-mic $W/<input>.mp4 "<UID>" default
K0=6 python3 $P/mute-offset-onsets.py $W/<input>.mp4
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"
```
Run the last two for AirPods, the Brio 500, the iPhone input (TKY Microphone) and a USB input. The probe
needs Screen Recording and Microphone for the shell, and a tone played aloud for the microphone to hear. For
each, write down the reported latency, the lag the probe prints, and the measured offset of the four events.
An input whose offset falls outside its lag goes back to Tim; the constants stay. Brio 500 ______ AirPods
______ iPhone ______ USB ______ (Reported today, in the design's Probes: USB inputs 0.0138 s, the MacBook
Pro Microphone 0.0422 s, both with a 0.300 s lag; the sandbox lets the app read these properties for the
default input.) Do the offsets stay inside `max(0.3, 2 × reported + 0.05)`, and 0.6 s for AirPods?

## The twelve gaps, to confirm or overrule
The plan filled these where the design was silent; each was built as written (the built notes say how it
came out). Write `confirm` or `overrule` and why, then copy the result to the design's built notes.
- [ ] 1. Settings are read at the start: the hand-off reads the format, `GIF frame rate` and `GIF size`, so
  changing them in Settings during a recording or its conversion does not reach it. Check: start a GIF
  recording, switch `Format` to MP4 in Settings while it runs, Stop: it is still a GIF. ______
- [ ] 2. Notices after Stop come in a fixed order (`RecordingNoticeOrder`): the save's own notification
  (`GIF not made`, `Sound removed`, or `Recording saved`/`Sound not muted` from the plan), then `Recording
  stopped`, then the microphone note. `GIF not made` and `Sound removed` always post in normal mode, whatever
  Show notification says. Nothing posts in quit mode (D below). ______
- [ ] 3. `Recording.recoveryURL` is the MP4 for a GIF: when the GIF cannot leave `tmp/Recording`, `Not saved to a
  folder` names the MP4's path. (Not reachable by hand.) ______
- [ ] 4. Testable steps: `GIFConversion`, `RecordingRecovery.prepare` and `sweepMuteFolder`, and `RecordingMute.resolve`
  with its output URL and duration. Internal; nothing to see. ______
- [ ] 5. The GIF menu items come first in the status menu, after `Stop Recording` when one runs, then a
  separator; the percentage is rounded down and held at 99 % until the conversion has saved. ______
- [ ] 6. Microphone devices come through `MicrophoneDevices` (list, default, access, request). Settings reads
  its own `LiveMicrophoneDevices`, the recorder's loss reason the coordinator's. ______
- [ ] 7. Microphone loss mid-recording: the controller asks `microphoneLossReason` on `.outputFailed` and
  `.streamStopped`, giving `The microphone was disconnected.` or `Microphone access is off for TidyShot.`
  (needs H1 to see). ______
- [ ] 8. The mute log is `tmp/Mute/<id>.json`, created by the first write, made at the first toggle; a
  recording never muted has none. ______
- [ ] 9. Trim: the download posts `Downloading <key>` under `Opening the recording…`; `Trim…`, the sheet and `Upload
  Trimmed` read `hasUploadDestination` (built); the method is decided on the source before the mute step; a
  quit does not wait for a Trim pass; `trimWindows`, `trimPasses` and `trimmingIDs` live in the class body's
  Trim group (`trimWindows` is held with H2). ______
- [ ] 10. Rows: a Recent Captures row has no Retry; a video row gains `scissors` (`Trim…`) and, when shown,
  `arrow.up.circle` (`Upload Trimmed`) after Copy File; a marked row opens the file on a click and has no Copy
  File. The size gives way first when the detail is too wide. ______
- [ ] 11. Sizes (spec 2.13): a GIF's size is the GIF's after its move (after a failed conversion the MP4's); a muted
  recording's is the rewritten file's; Trim's is the trimmed file's (held with H2). Check a GIF's and a muted
  recording's row sizes against `ls -l`. ______
- [ ] 12. `saveRecording`'s new parameters: `saveNotice:`, `unmutedIntervals:` (built) and `microphoneNote:` (held
  with H1), each defaulting to none so R1's callers compile. Internal; nothing to see. ______

Four more where the build made a call the design did not settle. Each needs Tim's confirm or overrule
before merge:
- [ ] A. `GIFMakerError.couldNotRead` (`The recording could not be read.`) is the body when a recording cannot be
  read for conversion: `GIF not made` / `The recording could not be read. The recording was saved as an MP4.` ______
- [ ] B. The marked card keeps a disabled `Copy URL` (a marked record never has a link). Leave it, or drop it? ______
- [ ] C. The cache note's title when a replaced upload's URL was not copied is `Uploaded` (the copied branch's `Uploaded,
  URL copied` would be untrue there). ______
- [ ] D. A recording that ends with nothing kept (`.nothing`) no longer posts `Recording failed` while TidyShot quits;
  R1 posted it. In quit mode no notice posts at all (`RecordingNoticeOrder.afterStop(… quitMode:)`). ______

## Regression
- [ ] ⌃⇧1 to ⌃⇧7 behave as in the 6a, 6b and 7b checklists after a GIF and after an MP4 recording.
- [ ] An MP4 recording with the defaults is what R1 made: `Recording saved`, the file in the save folder, the
  172 x 44 bar with no mute button when system audio is off, Clop `Optimizing…` and a smaller object.
- [ ] A screenshot's save, upload, Retry, Delete, Save As… and Copy Image are as before; a PNG still gets
  `.png` and `image/png`.
- [ ] Old history (a `history.json` from before R2) loads, with every record's `unmutedIntervals` empty and
  every R1 video still a video (the `isVideo` to `isTimeBased` rename).
- [ ] The Recent Captures menu opens at once with a GIF, a video and a screenshot among the rows.
- [ ] Quit TidyShot with nothing recording: it quits at once.
- [ ] Delete (and confirm) a GIF: the file, the record and any uploaded object go.

## Observations
Write these into the R2 design's Probes section (and the built notes for the gaps):
- The GIF sizes, times and memory against the spike's, and which content looks poor (posterisation, banding).
- Playback in Safari, Chrome, Firefox, Quick Look, Slack and a GitHub comment box.
- The sandboxed microphone run (Probe 4) and what the first prompt looked like.
- What ScreenCaptureKit did when access was turned off or the input unplugged mid-recording.
- Each input's measured offset against its lag (Probe 6).
- The trim probe on the 60 s recordings (Probe 5), and Tim's decisions on the four points (built notes, Trim).
- Whether the sandbox let Trim's put replace a file on another volume.
- Anything above that failed.
