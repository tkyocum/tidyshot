# TidyShot: screenshot MVP design and implementation plan

Date: 2026-10-19
Status: all eight open decisions in section 7 resolved on 2026-10-19. Ready for a detailed Phase 0 and Phase 1 implementation plan.

## 1. Goal

A native macOS menu bar app that reproduces the screenshot half of CleanShot X, and replaces CleanShot Cloud with upload to a user-defined S3-compatible bucket. The headline workflow:

1. Press a global hotkey.
2. Select an area, a window, or the full screen.
3. The image is saved, uploaded to the bucket under a short name, and the public URL lands on the clipboard.
4. A small overlay confirms the upload and offers copy, save, annotate, and drag-out.

Screen recording is out of scope for this plan. The architecture leaves room for it (see section 5).

## 2. Research summary

### 2.1 CleanShot X screenshot features, triaged

Tiers: **P0** is the MVP, **P1** follows once the upload loop is solid, **P2** is nice to have, **Skip** is not planned.

| Feature | CleanShot behaviour | Tier | Notes |
|---|---|---|---|
| Capture area | Drag-select with crosshair, magnifier, dimension readout, edge snapping | P0 | Core |
| Capture window | Hover highlights a window, click captures it | P0 | Core |
| Capture fullscreen | Captures the display under the cursor | P0 | Core |
| All-in-One mode | One hotkey, then pick mode from a small toolbar; locks size and aspect ratio; remembers last selection | P1 | Good default hotkey once area/window/fullscreen exist |
| Capture previous area | Re-capture the last rectangle | P1 | Cheap once selection is stored |
| Quick Access Overlay | Thumbnail in a screen corner after capture with copy, save, annotate, share, drag-out, auto-close, restore closed overlay, multi-display | P0 (minimal), P1 (full) | MVP shows upload status plus copy/save/drag; the rest in P1 |
| After-capture action | Preference: show overlay, save, copy, open editor, or upload automatically | P0 | Upload-and-copy-URL is the default this app exists for. Phase 3 adds "Upload only" (no local file kept), see 2.4 |
| Upload and copy link | One click, link copied | P0 | Replaced by S3 destination |
| Window with background | Padding plus wallpaper, custom image, or solid colour behind a window shot | P2 | Pure image compositing |
| Transparent window / shadow toggle | Keep or drop the window shadow | P1 | `ignoreShadowsSingleWindow` in ScreenCaptureKit |
| Freeze screen | Snapshot the display before selecting, so moving content is capturable | P1 | Capture full display first, then crop |
| Self-timer | Delay before capture | P1 | Trivial once capture exists |
| Hide desktop icons | Clean desktop during capture | P2 | Cover window at desktop icon level (sandbox-safe); not a Finder `defaults` write |
| Scrolling capture | Captures content taller than the screen, any app | P1 (own phase) | Hardest screenshot feature: synthetic scroll events and image stitching; requested explicitly, gets Phase 5 |
| Annotate | Arrow, rect, ellipse, line, pencil, highlighter, text, counter, blur, pixelate, redact, spotlight, crop; editable project file | P1 (basic set plus blur, pixelate, redact), P2 (spotlight/counter) | Biggest UI surface in the app. Blur, pixelate and a solid redact rectangle ship in the first editor release because screenshots of dashboards and terminals carry secrets |
| Background tool | 20 backgrounds, padding, presets, auto balance | P2 | Compositing step shared with "window with background" |
| Pin (floating screenshot) | Always-on-top window, opacity, nudge with arrows, lock mode | P1 | Small `NSPanel` |
| Text recognition (OCR) | Select area, copy text, QR codes | P2 | Apple Vision framework, on-device |
| Capture history | Recent captures with filter, restore, delete, one month retention | P1 | Also the retry queue for failed uploads. Phase 2 shipped a text menu; Phase 3 turns it into a gallery, see 2.4 |
| File naming template | Placeholders for date, app, counter; auto-increment | P0 | Shared with the S3 object key scheme |
| URL scheme | `cleanshot://capture-area?action=upload`, `capture-window`, `capture-fullscreen`, `all-in-one`, `self-timer` | P1 | Lets Raycast, Keyboard Maestro, and scripts drive the app |
| Screen recording, video editor, GIF | Full recording stack | Later | Separate plan |
| Cloud: comments, expiry, passwords, SSO, transcription | Hosted service features | Skip | Replaced by S3 |

### 2.2 Dropshare upload model (what to borrow)

Dropshare's S3-compatible connection fields: bucket name with optional subfolder, access key ID, secret key, server hostname, optional region, domain alias (CNAME to the bucket), plus flags for SSL, path-style URLs, omit ACL header, disable multipart, and pre-signed URLs. It has a Test Connection button. Per-connection upload preferences, visible in your screenshot for `snap.tky.io`: URL shortener (off), Randomize filenames with an 8-character example, Append integrity hash (SHA-256) to URL, and an optional landing page.

Takeaways for TidyShot:

- Model uploads as a `Destination` protocol with one implementation, `S3Destination`, so Backblaze B2, Cloudflare R2, MinIO, and Wasabi work via the S3 API without separate code.
- Keep the "domain alias" idea: the public URL is built from a configurable base URL template, not from the S3 endpoint. Your existing `https://snap.tky.io/<name>.png` keeps working.
- Offer three key schemes: random short name (default, length 6, configurable), date-based template, and original filename.
- Make the ACL header optional. Modern AWS buckets block ACLs by default; a bucket policy or CloudFront handles public reads instead.
- Skip URL shorteners and landing pages. Your domain is already short.

### 2.3 Platform findings

Verified against the macOS 27.0 SDK shipped with Xcode 27.1 on this machine:

- `SCScreenshotManager.captureImage(contentFilter:configuration:)` exists from macOS 14.0.
- `SCScreenshotManager.captureImage(in: CGRect)` exists from macOS 15.2. It is display-agnostic and takes a rect in global point space, which is exactly what an area selector produces.
- macOS 26 adds `SCScreenshotConfiguration` and `captureScreenshot(rect:configuration:)` returning `SCScreenshotOutput` with SDR and HDR images and a display intent setting.
- `CGWindowListCreateImage` is still declared but deprecated since macOS 14, and Sequoia shows extra system alerts for apps that use it. A forum report says macOS 27 betas returned grey images from it. Do not use it.
- Screen Recording permission (TCC) is required for any ScreenCaptureKit capture that is not driven by `SCContentSharingPicker`. The picker is Apple's own window chooser and is not usable for a drag-select rectangle. Plan for the one-time permission prompt and a first-run screen that explains it.
- `SCStreamConfiguration` exposes `showsCursor`, `ignoreShadowsSingleWindow`, `captureResolution`, `shouldBeOpaque`, and `includeChildWindows`, which cover the window-shot options above.

Prior art: macshot (GPL-3.0) is an open-source Swift app with S3-compatible upload and link copying. Useful for reading how others handled the upload UX. Its GPL licence rules out copying code into this private project, so its source is off limits; only its documented behaviour is used as reference. VivyShot, Capso, and Mio are ScreenCaptureKit-based but have no upload.

### 2.4 Features added after Phase 2 (2026-10-19)

**Recent captures gallery.** The Phase 2 "Recent Captures" text submenu becomes a gallery window opened from the menu bar: a grid of thumbnails of recent captures, newest first; hovering a thumbnail shows a larger preview; clicking a thumbnail copies its public URL (or the local file when it was never uploaded); a delete action removes the object from object storage (`S3Destination.delete`), the history record, and the local file if present, after one confirmation. Thumbnails are generated at capture time and stored under Application Support next to `history.json`, so they survive deletion of the original and the "Upload only" mode below. Failed uploads keep their retry action in the gallery.

**Delete from the overlay.** The Quick Access overlay gets a Delete action for the capture just taken: it removes the object from storage, the history record, the thumbnail, and the local file, with a single confirmation, so a bad shot can be killed and retaken in two clicks. It shares the implementation with the gallery delete. While the upload is still in flight, Delete cancels it first (the upload queue gains a cancel for that record) and then removes whatever was written.

**Upload only mode.** A third after-capture action, "Upload only, keep no local file": the PNG is written to a temporary folder inside the app container (no save-folder prompt), uploaded, the URL copied, and the temporary file deleted on success. On failure the file stays until the retry succeeds or the record is deleted, so a capture is never lost. The history record then has no local file and shows only the thumbnail and URL.

**Blur, pixelate, redact in the editor.** Promoted into the first annotation release (see the Annotate row).

**Object key templates.** The object key becomes a template, defaulting to `{random:6}` so current behaviour is unchanged. Tokens: `{random}` (6 characters) and `{random:N}`, `{date}` (yyyy-MM-dd), `{year}`, `{month}`, `{day}`, `{time}` (HH-mm-ss), `{datetime}`, `{hostname}` (the Mac's local hostname, lowercased, without `.local`), `{app}`, and `{counter}`; literal text and `/` separators are allowed, so `shots/{year}/{month}/{hostname}-{random:8}` is valid. The `.png` extension is appended. The engine is shared with the local file-name template (`FileNamer`), so both use one token set; the key prefix field folds into the template. Keys are URL-safe: literal text is restricted to `[A-Za-z0-9._-/]` and tokens never emit anything else. The HEAD-before-PUT collision check stays, and a template without `{random}` or `{counter}` gets a warning in Settings because collisions then only resolve by the HEAD check.

**Scrolling capture.** Promoted from "extras" to its own phase (see the Scrolling capture row). Design sketch: the user picks a window or area; the app captures a frame, posts a scroll-wheel event to the target (`CGEvent`, which needs the Accessibility permission, so a second first-run flow), captures again, and stitches frames by locating the overlap with a row-signature match; stops when two consecutive frames are identical or the user clicks. Horizontal scrolling and a manual "scroll yourself" mode come after vertical works.

### 2.5 Feedback after the Phase 3 build (2026-10-19)

**Recent Captures as a hover submenu.** The gallery window is replaced. The menu bar moves from SwiftUI `MenuBarExtra` to an AppKit `NSStatusItem` with an `NSMenu`, because the "Recent Captures" item must open on hover and hold rows with custom views. Its submenu lists the newest captures (up to 15), each row a custom view: thumbnail, name, relative time ("2 minutes ago"), and three small icon buttons: copy URL, copy image, delete. Clicking the row copies the URL (or the file when never uploaded) and closes the menu. Hovering the thumbnail shows the full-size image in a floating preview panel placed to the left of the submenu; it follows the hovered row and hides when the menu closes. Copy image puts the PNG and TIFF on the clipboard from the local file, or downloads the object with a signed GET when no local file exists (upload-only captures), with a short notification while it downloads. Delete is the same single delete path as the overlay.

**Simpler delete confirmation.** The alert reads "Delete this capture?" with one line naming where the capture disappears from ("Removes it from object storage, your save folder and history." when a save-folder file exists, "Removes it from object storage and from history." otherwise) and two buttons, Delete and Cancel. Deleting implies removing the history entry. If the storage DELETE fails, a second alert offers "Remove from history anyway?" with Remove and Cancel, so a record whose object cannot be deleted is never stuck. The three-button alert from 2.4 is withdrawn.

**No `{app}` token.** Removed from both templates, the captions, and the README. Stored templates containing `{app}` are migrated by dropping the token and collapsing any doubled separator.

**Upload settings clarity.** Endpoint and Public URL fields show a neutral "Required" prompt; the example value sits in a caption under each field, so an unfilled field cannot be mistaken for a filled one. Save and Test Connection reports success without echoing the probe URL.

**Adaptive crosshair.** The selection crosshair samples the frozen snapshot under the cursor and draws black on light backgrounds and white on dark ones; before the snapshot arrives it is white with a one-pixel dark edge.

## 3. Core workflow in detail

```
hotkey ─▶ SelectionOverlay ─▶ CaptureEngine ─▶ CaptureRecord (PNG on disk + metadata)
                                                     │
                                  ┌──────────────────┼──────────────────┐
                                  ▼                  ▼                  ▼
                           Clipboard (image)   UploadQueue         QuickAccessOverlay
                                                     │                  ▲
                                             S3Destination.put ─────────┘ (progress, result)
                                                     │
                                            Clipboard (URL) + notification
```

Behavioural rules:

- The file is written to the local save folder before upload starts, so a failed upload loses nothing.
- When auto-upload is on, only the URL is written to the clipboard, on upload success. A setting ("Also copy image") additionally writes the image at capture time; the URL then replaces it. When auto-upload is off, the image is copied at capture time.
- The overlay shows a progress ring during upload, then a checkmark and the URL. Clicking it copies the URL again. Dragging it out drags the local file.
- Upload failures stay in capture history with a retry button and a notification. The app never silently drops a capture.
- One menu bar icon state change during upload, so the overlay can auto-close without losing the signal.

## 4. Technical foundation

| Concern | Choice | Reason |
|---|---|---|
| Language / UI | Swift 6, SwiftUI for the menu bar menu (`MenuBarExtra`), settings, and overlay content; AppKit for the selection overlay and panels. If the Phase 2 capture-history menu needs thumbnails, the menu moves to `NSMenu` | Selection overlay needs `NSWindow` level control, mouse tracking, and multi-display geometry that SwiftUI does not expose |
| Minimum macOS | 26.0 (decided 2026-10-19) | Uses `SCScreenshotConfiguration` and `captureScreenshot(rect:configuration:)` with `SCScreenshotOutput`, one API path, HDR available |
| App type | Menu bar agent (`LSUIElement`), no Dock icon by default | Matches CleanShot and Dropshare |
| Capture | ScreenCaptureKit only | See 2.3 |
| Global hotkeys | `KeyboardShortcuts` package (sindresorhus) | Mature, has a SwiftUI recorder view, uses Carbon hotkeys under the hood so no Accessibility permission is needed |
| Secrets | Keychain via `Security` framework; access key ID and secret per destination | Never in `UserDefaults` or plist |
| S3 client | Hand-rolled SigV4 signer over `URLSession`, single `PUT Object` request, optional `x-amz-acl: public-read` | One request type is needed; Soto pulls in about 20 packages and a large binary. Multipart is unnecessary for screenshots. Add Soto later only if recordings need multipart |
| Image encoding | `ImageIO` for PNG and JPEG, with a DPI tag matching the display scale | Retina images should report 144 DPI so they display at the right size when pasted |
| Persistence | Capture history and settings in `~/Library/Application Support/TidyShot/` as JSON plus files; `UserDefaults` for simple preferences | Small data, no need for Core Data |
| Distribution | Developer ID signed and notarized, outside the App Store. Hardened runtime on, App Sandbox on (decided 2026-10-19) | Entitlements: `network.client`, `files.user-selected.read-write`, `files.bookmarks.app-scope`. Save folder chosen via `NSOpenPanel` and persisted as a security-scoped bookmark. Keeps the App Store open as a later channel |
| Tests | Swift Testing for the signer (verify against AWS published SigV4 test vectors), naming templates, URL builder, and history store. Manual test checklist for capture UI | Capture UI cannot be unit tested meaningfully |
| Build | XcodeGen from `project.yml` (decided 2026-10-19); `TidyShot.xcodeproj` is gitignored and regenerated with `xcodegen generate` | Readable diffs, no merge conflicts in project files |

## 5. Architecture

Each module is a Swift Package target or a folder with one clear owner. Names are suggestions.

- **CaptureEngine**: wraps ScreenCaptureKit via `SCScreenshotConfiguration` and `SCScreenshotOutput` (macOS 26). API: `captureArea(CGRect) async throws -> CGImage`, `captureWindow(SCWindow, options) async throws -> CGImage`, `captureDisplay(SCDisplay) async throws -> CGImage`. SDR image is the default output; HDR is kept as a later option. Also exposes `shareableContent()` for window enumeration and a `permissionState()` check. No UI.
- **SelectionOverlay**: full-screen borderless `NSWindow` per display at `.screenSaver` level. Modes: area, window, fullscreen. Draws dimming, crosshair, magnifier loupe, size label, and window highlight. Returns a `Selection` enum (`.area(CGRect, display)`, `.window(SCWindow)`, `.display(SCDisplay)`). Escape cancels. Freeze-screen mode shows a captured display image underneath.
- **CaptureRecord / HistoryStore**: value type with id, timestamp, file URL, pixel size, source app, upload state (`none`, `uploading(progress)`, `uploaded(URL)`, `failed(Error)`). Store persists records and prunes by age.
- **Naming**: template engine for local filenames and S3 object keys. Tokens: `{date}`, `{time}`, `{datetime}`, `{app}`, `{counter}`, `{random:N}`, `{ext}`. Separate templates for local file and object key, because `Screenshot 2026-10-19 at 11.56.03.png` on disk and `aSIS7.png` in the bucket are both desirable.
- **Uploader**: `Destination` protocol (`upload(fileURL, key) -> URL`, `test()`), `UploadQueue` actor with concurrency 1, retry with backoff, progress via `URLSessionTaskDelegate`. `S3Destination` holds endpoint, region, bucket, prefix, path-style flag, ACL flag, public URL template, and a Keychain reference for credentials.
- **S3Signer**: pure functions that produce SigV4 `Authorization` and `x-amz-*` headers for a request. Fully unit tested.
- **QuickAccessOverlay**: `NSPanel`, non-activating, at a configurable corner, stacking multiple captures. Hosts a SwiftUI view with thumbnail, progress, action buttons, and `NSDraggingSource` for drag-out.
- **Annotator** (P1): separate window and document model. Not in the MVP, but the `CaptureRecord` file URL is its input.
- **Pinner** (P1): floating `NSPanel` showing an image with opacity and lock mode.
- **Settings**: SwiftUI `Settings` scene. Tabs: General (hotkeys, after-capture action, save folder), Capture (cursor, shadow, freeze, timer, format), Upload (destinations list, test button, naming), Overlay (position, auto-close), Advanced (URL scheme, history retention).
- **AppCoordinator**: menu bar item, hotkey registration, and the single place that wires hotkey to overlay to engine to queue to UI. Also handles the URL scheme.
- **Recording** (future): would add a `RecordingEngine` next to `CaptureEngine` and reuse Uploader, History, Overlay, and Naming unchanged.

## 6. Phased implementation plan

Each phase ends with something usable. Phases 1 and 2 deliver the headline workflow.

### Phase 0: skeleton (half a day)
- Xcode project, menu bar agent, app icon placeholder, Settings window shell, `KeyboardShortcuts` dependency.
- First-run Screen Recording permission flow with explanation and a button that opens System Settings.
- Done when: app launches to the menu bar and shows permission state.

### Phase 1: capture and save (2 to 3 days)
- `CaptureEngine` with the three capture types.
- `SelectionOverlay` for area (crosshair, size label, magnifier) and window (hover highlight) and fullscreen.
- Save to a configurable folder with the local naming template, copy image to clipboard, system notification.
- Hotkeys for area, window, fullscreen.
- Done when: the app replaces the built-in `Cmd-Shift-4` for daily use.

### Phase 2: S3 upload and clipboard URL (2 to 3 days)
- `S3Signer` with tests against AWS SigV4 test vectors, `S3Destination`, `UploadQueue`.
- Upload settings tab: endpoint, region, bucket, prefix, credentials into Keychain, path-style toggle, ACL toggle, public URL template, Test Connection.
- Object key naming with random short names.
- After-capture action preference, default "upload and copy URL".
- Minimal `QuickAccessOverlay`: thumbnail, progress, URL, copy, auto-close.
- Capture history list in the menu with retry for failures.
- Done when: hotkey, drag, and paste a working `https://snap.tky.io/xxxxx.png` link into Slack within about two seconds of releasing the mouse.

### Phase 3: recent captures gallery and upload-only mode (3 to 4 days)
- Thumbnail generation at capture time, stored under Application Support; history records gain a thumbnail path and allow a nil local file.
- Gallery window from the menu bar: grid, hover preview, click copies URL, delete from object storage plus history plus local file with confirmation, retry for failures.
- Delete action on the Quick Access overlay, sharing the gallery's delete; cancelling an in-flight upload first.
- "Upload only" after-capture action: temp file in the container, upload, copy URL, delete on success, keep on failure.
- Object key templates (`{random:N}`, `{date}`, `{year}`, `{month}`, `{day}`, `{time}`, `{hostname}`, `{app}`, `{counter}`, literal folders) sharing the token engine with `FileNamer`; the key prefix field folds into the template.
- "Forget credentials" button in the Upload tab.

### Phase 3.1: feedback from the Phase 3 build (2 to 3 days)
- Menu bar on `NSStatusItem` + `NSMenu`; Recent Captures hover submenu with custom rows (thumbnail, name, relative time, copy URL, copy image, delete) and a floating full-size preview to the left of the submenu; gallery window removed.
- `S3Destination.download(key:)` (signed GET) for copy-image on upload-only captures.
- Two-button delete alert, with a "remove from history anyway" fallback only after a failed storage DELETE.
- `{app}` token removed with migration of stored templates.
- Upload tab: "Required" prompts with example captions; connection test result without the probe URL.
- Adaptive crosshair colour from the snapshot.

### Phase 4: annotation (1 to 2 weeks)
- Editor window with arrow, rectangle, ellipse, line, pencil, highlighter, text, crop, undo, colour palette, and from the first release blur, pixelate, and a solid redact rectangle.
- Save over, save copy, copy, upload from editor; overlay's Annotate button opens it.
- Then spotlight, counter, and an editable project format.

### Phase 5: scrolling capture (1 to 2 weeks)
- Accessibility permission flow for posting scroll events.
- Vertical scrolling capture of a window or area with automatic stop; stitching by overlap detection; preview before save or upload.
- Then horizontal scrolling and a manual mode.

### Phase 6: overlay and capture polish (2 to 3 days)
- Full overlay: save-as, drag-out, close and restore, stacking, multi-display.
- All-in-One mode and capture-previous-area.
- Freeze screen, self-timer, cursor and shadow options, window shot with transparent background.
- Pin to screen.
- URL scheme (`tidyshot://capture-area?action=upload` and friends).

### Phase 7: extras (as wanted)
- Background tool and window-with-background.
- OCR via Vision, QR codes.
- Hide desktop icons during capture.

### Later: screen recording
Separate design document. Will reuse Uploader, Naming, History, and Overlay.

## 7. Decisions needed before Phase 1 and 2

1. **Minimum macOS**: decided, 26.0. Capture uses `SCScreenshotManager.captureScreenshot(rect:configuration:)` and `captureScreenshot(contentFilter:configuration:)` with `SCScreenshotConfiguration`.
2. **Clipboard in upload mode**: decided, URL only, with an "Also copy image" setting off by default.
3. **Object key default**: decided, random 6 characters from `[A-Za-z0-9]` plus extension, configurable length (4 to 32) and an optional prefix folder. Amended 2026-10-19: the key is a template defaulting to `{random:6}` (see 2.4), which keeps this default while allowing dates, hostname, and literal folders. Collision handling: issue a `HEAD` on the key before `PUT` and regenerate on 200.
4. **Public read**: decided, rely on a bucket policy or CDN. No ACL header by default; a per-destination "Send public-read ACL" toggle adds `x-amz-acl: public-read`. Test Connection performs a PUT, then an unauthenticated GET on the public URL, and reports if the object is not readable.
5. **Image format default**: decided, PNG always. A per-destination format override (JPEG, HEIC, quality) is a Phase 3 item.
6. **Sandbox**: decided, on. Save folder access via security-scoped bookmarks. Consequences: on the first capture the app asks for a save folder with `NSOpenPanel` and keeps it as a security-scoped bookmark; drag-out from the overlay uses `NSFilePromiseProvider`; the "hide desktop icons" feature must be implemented as a wallpaper-coloured cover window at desktop icon level rather than a Finder `defaults` write; the URL scheme and Carbon hotkeys work unchanged.
7. **Licence**: decided, private and unlicensed for now. Do not read or copy macshot's GPL source; only its public documentation and UI behaviour may be used as reference. Revisit if the project is ever published.
8. **Project generator**: decided, XcodeGen. `project.yml` is the source of truth; `.xcodeproj` is ignored. Swift package dependencies are declared in `project.yml`.

## 8. Risks

- **Permission prompt UX**: the first capture fails until Screen Recording is granted and the app is relaunched. Mitigate with the Phase 0 first-run flow.
- **Coordinate systems**: AppKit uses bottom-left origin per screen; ScreenCaptureKit rects for `captureImage(in:)` are in global display-space points. Multi-display with mixed scale factors is where selectors break. Build a `Geometry` helper early and test on two displays.
- **Retina sizing**: a 2x capture pasted into another app shows at double size unless the PNG carries DPI metadata. Handle in the encoder, not per caller.
- **SigV4 edge cases**: object keys with spaces or unicode, and S3-compatible providers that disagree on canonical URI encoding. Random ASCII keys avoid most of it; test against R2 and B2 as well as AWS.
- **ScreenCaptureKit latency**: `captureImage` is async and takes tens of milliseconds. Fine for a single shot, and freeze-screen mode hides it entirely.
- **macOS 27 is new**: some of the macOS 26 screenshot API may have behavioural changes. Keep `CaptureEngine` thin so a fallback path is cheap.

## 9. Sources

- CleanShot X features: https://cleanshot.com/features
- CleanShot X URL scheme: https://cleanshot.com/docs/api
- Dropshare S3-compatible connections: https://kb.dropshare.app/set-up-an-upload-connection/how-to-set-up-s3-api-compliant-connections.html
- Dropshare S3 overview: https://dropshare.app/blog/posts/11-upload-screenshots-to-amazon-s3-on-mac
- Dropshare upload preferences screenshot: https://snap.tky.io/aSIS7.png
- Apple forums on CGWindowListCreateImage and ScreenCaptureKit: https://developer.apple.com/forums/thread/740493 and https://developer.apple.com/forums/thread/849969
- Screen Recording permission behaviour on Sequoia: https://developer.apple.com/forums/thread/760483
- macshot (GPL-3.0, S3 upload prior art): https://alternativeto.net/software/macshot/about
- VivyShot (ScreenCaptureKit prior art): https://github.com/vivy-company/vivyshot
- KeyboardShortcuts package: https://github.com/sindresorhus/KeyboardShortcuts
- Soto (full AWS SDK alternative): https://swiftpackageindex.com/soto-project
- Local SDK headers inspected: `MacOSX27.0.sdk/.../ScreenCaptureKit.framework/Headers/SCScreenshotManager.h`
