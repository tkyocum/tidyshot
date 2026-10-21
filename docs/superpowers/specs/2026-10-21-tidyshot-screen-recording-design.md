# TidyShot screen recording: design draft (2026-10-21)

Status: **draft, waiting on Tim's answers** to the questions at the end. Section 6 of the screenshot design (`2026-10-19-tidyshot-screenshot-design.md`) said recording gets its own design document and reuses Uploader, Naming, History and Overlay. Nothing here is built.

## Goal

Record an area, a window or a whole display to a video file. Then treat it like a screenshot: save it to the save folder or keep it upload-only, upload it to the S3 destination, copy the link, and show it in Quick Access and Recent Captures.

## What the existing app gives us

- **Capture.** ScreenCaptureKit, with the Screen Recording permission already granted. The area, window and display selection overlays from Phases 1 and 6 can choose what to record. Self-timer's countdown panel can count in.
- **Naming and keys.** `FileNamer`, `ObjectKeyNamer` and the key template already take an extension, and `UploadJob` takes `contentType` and `fileExtension`, so `.mp4` and `video/mp4` fit.
- **Uploads.** `S3Destination.upload(_ data: Data, …)` sends one PUT from memory. That is fine for a PNG, but a few minutes of Retina video is hundreds of MB. Recording needs an upload from a file, and above a threshold (S3 recommends 100 MB) a multipart upload. This is the largest change outside the recorder itself.
- **History, cards and Recent Captures.** These assume an image: thumbnails, pixel size, Copy Image, Annotate, Pin. Records need a media kind, and the image-only actions must be hidden for videos.
- **Clop.** Clop optimises videos too, through the same port, but it can take a long time. Section 2.7's 30 s receive timeout is for images.

## Engine

- **Recording.** ScreenCaptureKit's `SCRecordingOutput` (macOS 15 and later) writes the stream straight to a `.mov` or `.mp4`, choosing H.264 or HEVC. No `AVAssetWriter` code is needed.
- **Sources.**
  - An area records the display filter with `sourceRect`.
  - A window records `SCContentFilter(desktopIndependentWindow:)`.
  - A display records the whole screen.
- **Excluded from the recording.** TidyShot's own recording frame, the control panel and the Quick Access cards, as captures exclude cards today.
- **Probe status.** A command-line probe compiles against the macOS 27 SDK and lists the configuration. Run from the shell, it trapped inside ScreenCaptureKit before recording (`__NSArray0` release, SIGTRAP), most likely because a bare command-line tool lacks a run loop or a bundle. It needs repeating as a small app bundle before any plan is written.
- **Audio.**
  - System audio: `SCStreamConfiguration.capturesAudio`. No new entitlement.
  - Microphone: `captureMicrophone` (macOS 15 and later). This needs the `com.apple.security.device.audio-input` entitlement, an `NSMicrophoneUsageDescription` and a TCC prompt.
- **Frame rate and size.** `minimumFrameInterval` (30 or 60 fps), and the output at Retina or 1x size. File size roughly scales with both.

## Flow (proposed)

1. **Start.** `Record Screen` from the menu or a new shortcut opens the selection overlay. Drag an area, click a window, or press Space for the display, as in All-in-One.
2. **Count-in.** An optional 3-second count-in, using the self-timer badge.
3. **While recording:**
   - a thin frame marks the recorded area;
   - a small floating control panel, excluded from the recording, shows the elapsed time, Stop, Pause and Cancel;
   - the menu bar icon becomes a stop button;
   - the shortcut stops the recording, and Escape cancels it.
4. **Stop.** The file is finished, a first-frame thumbnail is made, and the after-capture action runs as for a screenshot: save, upload, copy the link. The clipboard gets the URL, or with upload off the file itself, not an image.
5. **Quick Access.** The card shows the thumbnail, the duration and a play badge; clicking opens the file in QuickTime. There is no Annotate, Pin or Copy Image for videos.

## Phasing (proposed)

- **R1:**
  - area, window and display recording to MP4 (H.264, 30 fps, Retina);
  - system audio;
  - control panel and stop;
  - save and upload, with file-based and multipart S3 uploads and progress;
  - video records in history, cards and Recent Captures.
- **R2:** microphone; GIF export with frame-rate and width caps; trim before upload; Pause.
- **R3:** click highlights, keystroke overlay, webcam bubble.

## Questions for Tim

1. **Formats.** Is MP4 enough for R1, or do you want GIF from the start? GIFs are large and lossy, but they play inline everywhere.
2. **Microphone.** Should R1 record the microphone? It adds an entitlement and a permission prompt.
3. **Quality.** Should the default be 30 fps at Retina size, 60 fps, or 1x size to keep files small?
4. **Clop.** Should videos go through Clop before upload? It can take minutes for long recordings.
5. **Limits.** Should there be a length or size warning, for example past 5 minutes or 500 MB?
6. **Shortcut.** ⌃⇧8 for Record Screen? ⌃⇧7 is now Capture Text.
7. **Link behaviour.** Is a plain link to the `.mp4` fine, or do you want an HTML viewer page next to the video?
