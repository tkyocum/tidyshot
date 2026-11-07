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
| All-in-One mode | One hotkey, then pick mode from a small toolbar; locks size and aspect ratio; remembers last selection | P1 | Built in Phase 6b (2.9): ⌃⇧1 opens an adjustable selection (handles, arrows, W and H, aspect lock) with Capture, Window, Fullscreen, Scrolling and Timer, starting from the last area |
| Capture previous area | Re-capture the last rectangle | P1 | Built in Phase 6a (2.9): ⌃⇧6 captures the rect of the last area capture again, with no selection overlay |
| Quick Access Overlay | Thumbnail in a screen corner after capture with copy, save, annotate, share, drag-out, auto-close, restore closed overlay, multi-display | P0 (minimal), P1 (full) | MVP shows upload status plus copy/save/drag; Phase 6a (2.9) built the stack of cards, close and restore, the choice of display, Save As…, Copy Image and drag-out of a file; Phase 6b added Pin; swipe gestures and hide-temporarily are deferred |
| After-capture action | Preference: show overlay, save, copy, open editor, or upload automatically | P0 | Upload-and-copy-URL is the default this app exists for. Phase 3 adds "Upload only" (no local file kept), see 2.4. "Open editor" is still deferred (Phase 4c built only Spotlight and Counter, 2.12); Phase 4 opens the editor from the overlay and Recent Captures, see 2.6 |
| Upload and copy link | One click, link copied | P0 | Replaced by S3 destination |
| Window with background | Padding plus wallpaper, custom image, or solid colour behind a window shot | P2 | Built in Phase 7c (2.11): a Capture setting puts each window capture on the style chosen under Edit Background…, composed in `AppCoordinator.save` |
| Transparent window / shadow toggle | Keep or drop the window shadow | P1 | Built in Phase 6a (2.9): `ignoreShadows` follows `Include window shadow`; the system shadow, sized from the filter's contentRect and pointPixelScale |
| Freeze screen | Snapshot the display before selecting, so moving content is capturable | P1 | Built in Phase 6a (2.9): every display is captured before the overlay appears and the capture is cut from that picture |
| Self-timer | Delay before capture | P1 | Built in Phase 6b (2.9): select an area or a window, then a 3, 5 or 10 second countdown; Escape cancels |
| Hide desktop icons | Clean desktop during capture | P2 | Built in Phase 7b (2.10): one panel per display shows the captured wallpaper window just above the icons and widgets, during most captures (a Capture setting) or until turned off (a menu item and three URL commands); not a Finder `defaults` write |
| Scrolling capture | Captures content taller than the screen, any app | P1 (own phase) | Hardest screenshot feature; gets Phase 5, designed in 2.8. Manual mode first (the user scrolls, TidyShot captures and stitches; Screen Recording only), then opt-in auto-scroll that posts scroll-wheel events behind the PostEvent permission (listed as Accessibility in System Settings). Vertical only; horizontal is deferred |
| Annotate | Arrow, rect, ellipse, line, pencil, highlighter, text, counter, blur, pixelate, redact, spotlight, crop; editable project file | P1 (basic set plus blur, pixelate, redact), P2 (spotlight/counter) | Built in Phase 4c (2.12): Spotlight (`S`) and Counter (`N`), the last two tools; Phases 4a and 4b (2.6) built the rest, and the editable project file is still deferred. Biggest UI surface in the app. Blur, pixelate and a solid redact rectangle shipped in the first editor release because screenshots of dashboards and terminals carry secrets |
| Background tool | 20 backgrounds, padding, presets, auto balance | P2 | Built in Phase 7c (2.11): twelve gradients, the desktop picture, a solid colour or one custom image, with padding, corner radius, shadow and an aspect ratio; auto balance and named presets are deferred |
| Pin (floating screenshot) | Always-on-top window, opacity, nudge with arrows, lock mode | P1 | Built in Phase 6b (2.9): a non-activating panel per pin with move, resize, zoom, opacity, arrows, lock (click-through) and a context menu; pins live until quit |
| Text recognition (OCR) | Select area, copy text, QR codes | P2 | Built in Phase 7b (2.10): Capture Text (⌃⇧7) puts the text of a selection, or its two-dimensional codes' payloads, on the clipboard, with Vision on-device |
| Capture history | Recent captures with filter, restore, delete, one month retention | P1 | Also the retry queue for failed uploads. Phase 2 shipped a text menu; Phase 3 turns it into a gallery, see 2.4 |
| File naming template | Placeholders for date, app, counter; auto-increment | P0 | Shared with the S3 object key scheme |
| URL scheme | `cleanshot://capture-area?action=upload`, `capture-window`, `capture-fullscreen`, `all-in-one`, `self-timer` | P1 | Built in Phase 6b (2.9): `tidyshot://` with CleanShot's command names, actions and bottom-left coordinates; commands that capture without a selection are off until allowed in General |
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

**Scrolling capture.** Promoted from "extras" to its own phase (see the Scrolling capture row). The user picks an area or a window and TidyShot stitches frames of it by locating the overlap with a row-signature match. The first sketch had the app post scroll-wheel events (`CGEvent`, then thought to need the Accessibility permission as a second first-run flow), stop when two consecutive frames are identical or the user clicks, and add a manual "scroll yourself" mode and horizontal scrolling after vertical worked. Phase 5 reversed that order and changed the permission: manual mode comes first and needs only Screen Recording; auto-scroll is an opt-in layer on the same engine behind the PostEvent permission (`CGPreflightPostEventAccess`, which System Settings lists under Accessibility; no Accessibility API and no entitlement), and it ends after two unchanged screens or when the user clicks Done. Horizontal scrolling is deferred. See 2.8.

### 2.5 Feedback after the Phase 3 build (2026-10-19)

**Recent Captures as a hover submenu.** The gallery window is replaced. The menu bar moves from SwiftUI `MenuBarExtra` to an AppKit `NSStatusItem` with an `NSMenu`, because the "Recent Captures" item must open on hover and hold rows with custom views. Its submenu lists the newest captures (up to 15), each row a custom view: thumbnail, name, relative time ("2 minutes ago"), and three small icon buttons: copy URL, copy image, delete. Clicking the row copies the URL (or the file when never uploaded) and closes the menu. Hovering the thumbnail shows a larger image (up to 560 by 420 points) in a floating preview panel placed on the side of the submenu away from the status menu, falling back to the other side when there is no room and always kept on screen; it follows the hovered row and hides when the menu closes. Copy image puts the PNG and TIFF on the clipboard from the local file, or downloads the object with a signed GET when no local file exists (upload-only captures), with a short notification while it downloads. Delete is the same single delete path as the overlay.

**Simpler delete confirmation.** The alert reads "Delete this capture?" with one line naming where the capture disappears from ("Removes it from object storage, your save folder and history." when a save-folder file exists, "Removes it from object storage and from history." otherwise) and two buttons, Delete and Cancel. Deleting implies removing the history entry. If the storage DELETE fails, a second alert offers "Remove from history anyway?" with Remove and Cancel, so a record whose object cannot be deleted is never stuck. The same second alert, with "The file stays where it is.", follows when the file in the save folder cannot be removed (it lies outside the current save folder, for example after another folder was chosen, or the folder's bookmark no longer resolves); any object this capture alone owned has been deleted by then (shared keys and pre-Phase 3 records keep theirs), so without it the record could never leave history. A second alert waits until no menu is open. The three-button alert from 2.4 is withdrawn.

**No `{app}` token.** Removed from both templates, the captions, and the README. Stored templates containing `{app}` are migrated by dropping the token and collapsing any doubled separator.

**Upload settings clarity.** Endpoint and Public URL fields show a neutral "Required" prompt; the example value sits in a caption under each field, so an unfilled field cannot be mistaken for a filled one. Save and Test Connection reports success without echoing the probe URL.

**Adaptive crosshair.** The selection crosshair samples the frozen snapshot under the cursor and draws black on light backgrounds and white on dark ones; before the snapshot arrives it is white with a one-pixel dark edge.

**Loupe crosshair (feedback after the Phase 3.1 build, 2026-10-20).** The cross inside the loupe stayed white, so over light pixels it vanished while the main crosshair turned black, and the 1 pt crosshair at 0.8 alpha was faint on any background. Both become two-tone strokes in the first task of Phase 4; see "Crosshair and loupe contrast" in 2.6.

### 2.6 Phase 4 design: the annotation editor (2026-10-20)

**Scope, order and release.** Phase 4 is one release delivered as two PRs: 4a landed as PR 7 from the branch `phase-4-annotation` (merge commit 9193586), and 4b is PR 2 from the branch `phase-4b-annotation`.
- **4a (PR 7).** In order: the loupe and crosshair contrast fix; the editor model, rendering, undo and tools, with an end-to-end redaction export test; a window with Select, Redact, Pixelate, Blur, Rectangle and Arrow, the colour palette, line widths and zoom; the four actions (Save, Save As…, Copy, and Upload with Upload as New; Save As… replaced Save Copy after the 4a build); and the Annotate entry points on the Quick Access overlay and on Recent Captures rows. Redaction lands first because screenshots of dashboards and terminals carry secrets, and the 4a build can be used and tested before the drawing tools exist.
- **4b (PR 2).** Ellipse, Line, Pencil, Highlighter, Text and Crop, then keyboard polish (duplicate, object copy and paste, Space-drag pan) and canvas accessibility.
- **The Phase 4 release is 4a plus 4b.** Section 6 and the Annotate row (P1, "basic set plus blur, pixelate, redact") put ellipse, line, pencil, highlighter, text and crop in the first editor release next to the effects. The two PRs are an order of work, not a smaller first release.
- **4c (after the release, P2).** Spotlight, Counter, the editable project format, and "open editor" as an after-capture action (deferred from the 2.1 row: the overlay and Recent Captures cover the need in Phase 4, while a fourth after-capture action touches `save(_:)` and the Settings picker). Phase 4c (2.12) built Spotlight and Counter only; the other two are still later (the Phase 4c list below).

**Feedback after the 4a build (2026-10-20).** Tim's notes on PR 7, folded into the sections below:
- The toolbar lost its menus and its overflow chevron. Copy, Save (`square.and.arrow.down`) and Upload (`icloud.and.arrow.up`, prominent) are plain buttons, and the window's minimum content width is the toolbar's width, so every item shows.
- Save Copy is gone. Save As… (⇧⌘S, `saveDocumentAs:`) opens a save panel and writes a PNG wherever the user picks, without a new capture. ⌘S with no local file to write over (an uploaded upload-only capture, a file outside the save folder, no folder) runs Save As… instead of uploading another copy or doing nothing.
- Upload uploads at once and closes the window once the upload is under way; the link lands on the clipboard when it finishes. An edit with no file to write over goes to `pending/<id>.png` first, so it is never only in the upload. Upload as New is ⌥⌘U only.
- The close sheet's Save follows ⌘S (and so may open the save panel); while Save is unavailable it reads Save As….

**Crosshair and loupe contrast.** After the Phase 3.1 build the cross inside the loupe was still hard-coded white, and the 1 pt crosshair at 0.8 alpha was too faint. Every stroke `SelectionView` draws through `stroke(_:)` (the crosshair, the drag rectangle border, the completed rectangle border) and the loupe's cross become two-tone: an opaque 1 pt line in the style's colour over a halo one device pixel wider on each side in the opposite colour at 0.7 alpha. `CrosshairStyle` (Luminance.swift) carries the colour table so it can be tested like the thresholds:
- `var lineWhite: CGFloat`: 0 for `.dark`, 1 for `.light` and `.outlined`.
- `var haloWhite: CGFloat`: 1 for `.dark`, 0 for `.light` and `.outlined`.
- `static let lineAlpha: CGFloat = 1` and `static let haloAlpha: CGFloat = 0.7`.

The cases keep their meaning: `.dark` over light pixels (black line, white halo), `.light` over dark pixels (white line, black halo), and `.outlined` when no luminance is available (white line, black halo, the same colours as `.light`). In `drawLoupe(at:)`, `stroke(cross)` replaces the hard-coded `NSColor.white.withAlphaComponent(0.9)` cross. `style(at:)` already samples a 24 pt square (`Luminance.sampleSide`) that encloses the loupe's 16 pt region, so no second sample is needed. The loupe's 2 pt white ring is unchanged. No loupe is drawn before the snapshot arrives (`drawLoupe` returns when `snapshot` is nil), so the loupe sees `.outlined` only when the sample lies wholly outside the snapshot.

**Architecture.** AppKit owns the editor window, toolbar, canvas, events and menus. SwiftUI appears only as the content of two NSPopovers (colour palette and tool options), hosted by `NSHostingController` with `sizingOptions = .preferredContentSize`. New code lives in `TidyShot/Editor/`, in seven subfolders:
- `Model/`: nonisolated, Sendable, Codable value types.
- `Geometry/`: pure nonisolated helpers.
- `Rendering/`: one actor, one MainActor cache, and nonisolated CoreGraphics drawing.
- `Session/EditorModel.swift`: MainActor, `@Observable`.
- `Tools/`: MainActor tool classes behind protocols, plus `ToolFactory.swift` with `makeTool(for:)`. Its exhaustive switch makes the compiler flag every new `EditorTool` case.
- `Window/`: AppKit views, `EditorToolbar.swift` and the window controller.
- `Persistence/`: pure decision tables for the four actions, the clipboard and the shortcut gate.

XcodeGen's recursive `TidyShot` source path picks the folders up with `xcodegen generate` alone.

The coordinator side lives in `AppCoordinator+Editor.swift`, an `extension AppCoordinator` file. It calls internal members of the coordinator declared in the coordinator's other files, for example `startUpload(recordID:payload:destination:fixedKey:)`, `imageData(of:downloadTitle:)`, `deleteObjects(_:at:)`, `keepOnClipboard(_:png:alreadyOnClipboard:)`, `refreshOverlay(for:)`, `notifier`, `overlay` and `deletingIDs`. Every branch the coordinator takes comes from a tested helper in `Editor/Persistence/`.

A new `nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }` (TidyShot/Output/ScaledImage.swift) is the only type that crosses between the editor and the coordinator. It exists because `CaptureResult` requires a MainActor `CaptureTarget`. `CaptureResult` gains `var scaled: ScaledImage`. The editor never writes files, never touches the pasteboard and never enqueues uploads. AppCoordinator stays the one save path, the one upload path and the one delete path.

**Concurrency rule.** Under `SWIFT_APPROACHABLE_CONCURRENCY` (NonisolatedNonsendingByDefault), a `nonisolated async` function runs on the caller's executor. Any nonisolated async function that must run off the main actor is therefore marked `@concurrent`. Detached tasks and actor methods are unaffected:
- `RedactionRenderer` is an actor, so its methods run on its own executor.
- `EditorModel.renderExport` flattens inside `Task.detached`.
- The test `FakeTileRenderer.tile` is `@concurrent` and waits on an async gate (an `actor TileGate` holding a `CheckedContinuation`), never on a `DispatchSemaphore`. A semaphore would block the main actor that the MainActor tile-cache tests run on, and deadlock.

**Document model.** All model geometry is in image pixels with a top-left origin (CGImage row 0). This is the same convention as `Luminance.mean(of:in:)` and `CGImage.cropping(to:)`.
- `RGBA` holds `red, green, blue, alpha: Double` in sRGB and derives `cgColor`. The model never stores a CGColor, CGPath, NSColor or CIFilter; CGPath and CIFilter are not Sendable in the 27 SDK.
- The payload structs are `ShapeBox { id: UUID; rect: CGRect; color: RGBA; lineWidth: CGFloat }`, `Segment { id; from: CGPoint; to: CGPoint; color; lineWidth }` and `Region { id; rect }`.
- `enum Annotation: Identifiable, Equatable, Sendable, Codable` has the 4a cases `rectangle(ShapeBox)`, `arrow(Segment)`, `redact(Region, fill: RGBA)`, `blur(Region, radius: CGFloat)` and `pixelate(Region, block: CGFloat)`. 4b added `ellipse(ShapeBox)`, `line(Segment)`, `pencil(Stroke)`, `highlighter(Stroke)` and `text(TextBox)`. `Stroke { id; points: [CGPoint]; color; lineWidth }` keeps the decimated pointer samples, and the smoothed curve is rebuilt from them each time it is drawn or hit (`StrokeSmoothing.path(for:)`), so no CGPath is stored. `TextBox { id; string; origin: CGPoint; fontSize: CGFloat; color }` keeps the top-left corner of the text's frame (`TextLayout.frame(for:)`) and a font size in image pixels; lines break at newlines only. `Annotation.title` (`Rectangle`, `Arrow`, `Ellipse`, `Line`, `Pencil`, `Highlighter`, `Text`, `Redact`, `Blur`, `Pixelate`) names undo steps and accessibility labels.
- Line widths, blur radii and block sizes are stored in image pixels: the points chosen in the UI times the capture scale at creation. Export therefore needs no conversion, and a 2x capture gets twice the pixels.
- `isEffect` is true for redact, blur and pixelate. Effects belong to the base layer: they render beneath every drawing, in creation order.
- `struct AnnotationDocument: Equatable, Sendable, Codable { var annotations: [Annotation] }` exposes `effects` and `drawings` (both in creation order), `annotation(id:)`, `appending(_:)`, `removing(id:)`, `replacing(_:)` and `moving(id:by:)`. 4b added `crop: CGRect?` (decodeIfPresent): the part of the capture export keeps, in whole image pixels inside the image and never the whole capture (`CropGeometry.integralCrop` stores nil for that).
- The base CGImage is not part of the document. EditorModel holds it next to the document and never mutates it.
- No file in Phase 4 persists the document. The only file on disk with unredacted pixels is the original the user chose not to overwrite. The clipboard rule below covers the one other copy.

**Rendering.** The window's content view stacks two viewport-sized views. There is no document-sized view and no NSScrollView magnification. This avoids `_NSTiledLayer` seams and a 10240x5760 backing store for a 5K capture.

*`BaseImageView`* is flipped and layer-backed, and its `hitTest` returns nil. It shows:
- the capture as one `CALayer.contents` texture, with implicit actions disabled; an image over 16,384 px on a side (a scrolling capture, 2.8) as stacked layers, one per `ImageTiling` tile, each a cropped CGImage sharing the capture's pixels and framed at `transform.viewRect(rect)` like the effect tiles;
- one sublayer per effect tile, in creation order, each framed at `transform.viewRect(rect)`.

Zoom and pan only move layer frames. All layers use `magnificationFilter = .nearest` when `zoom * backingScale >= 2` and `.linear` below, with `.trilinear` minification, so redacted pixels read exactly when zoomed in.

*`CanvasView`* sits on top. It is flipped and layer-backed, not opaque, with `layerContentsRedrawPolicy = .onSetNeedsDisplay`. Its `draw(_:)` works only within the dirty rect:
1. Concatenates `transform.affine`, so drawing is in image pixels.
2. Draws placeholders for pending effects: the fill colour for a pending redact, grey at 0.5 alpha for a pending blur or pixelate.
3. Draws every drawing whose bounds meet the dirty rect, then the transient shape, through `AnnotationDrawing.draw(_:in:scale:)`.
4. Restores the CTM, then draws selection handles (8 pt squares) and a dashed outline (for a selected effect, stroke or text; a text has the outline and no handles). Both are drawn in view space so they keep a constant size. While the Crop tool is active, this step instead draws the crop chrome and no selection: the image outside the draft dimmed (black at 0.5), the draft's 1 pt edge and eight handles, and a `W × H` readout in image pixels in a dark pill under the draft's bottom-left corner. With a crop applied, it paints the window background over everything outside the crop (`AnnotationDrawing.drawCropCover`), so the canvas shows what export keeps.

Before step 2, `drawHighlighterBackdrops` clips to each visible highlighter's stroked outline and draws the capture and the shown effect tiles into the clip, so the multiply has the pixels `BaseImageView` shows; the clip is 1 view point wider on each side so anti-aliased edge pixels get a whole backdrop, as in the export. `TileRepaint.dirtyRect` repaints the area a tile covered when it is replaced, moved or resized, so a highlighter over a blur follows the blur.

*Tiles.* `actor RedactionRenderer: TileRendering` owns the app's one `CIContext(mtlDevice: MTLCreateSystemDefaultDevice(), options: [.cacheIntermediates: true, .name: "TidyShot.redaction"])`, with `CIContext(options:)` as the fallback. Filters are built inside each call, because CIFilter is not Sendable. The method `tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) -> CGImage?` composites the earlier tiles under the input, then applies one of three graphs:
- **Blur:** `clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: rect)`.
- **Pixelate:** an averaged mosaic. It crops the block-aligned rect, applies `transformed(by: 1/block, highQualityDownsample: true)`, then `samplingNearest()`, scales back up and crops to the rect. The grid is anchored to image pixel (0,0), so the picture under a dragged region does not reshuffle. This is not `CIPixellate`, which point-samples.
- **Redact:** `CIImage(color:).cropped(to: rect)`.

Output always goes through `createCGImage(_:from:format: .RGBA8, colorSpace: base.colorSpace ?? sRGB, deferred: false)`, so no GPU work runs inside `draw(_:)`. The actor has two more methods: `warmUp(with:)` renders a 1x1 tile when an editor opens, and `clearCaches()` runs when the last editor closes.

Redact is a tile like the others, so a later blur or pixelate that overlaps a redaction blurs black, never the secret. `beneath` holds every earlier effect whose rect meets the later effect's sample rect, `EffectGeometry.sampleRect(of:imageSize:)`:
- for blur, the rect grown by `ceil(3 * radius)`;
- for pixelate, the block-snapped rect;
- for redact, the rect itself.

A blur next to a redaction therefore never smears secret pixels in from its margin.

*`RedactionTileCache`* (MainActor) keys each tile by `TileKey { effect: Annotation; beneath: [Annotation] }`. The key holds the effect's own value plus the values of the earlier effects it samples. A change to an earlier effect therefore changes the key of every later effect it touches, so no explicit invalidation pass is needed.
- `reconcile(document:transient:)` computes the wanted keys with the pure `RedactionTileCache.keys(for:imageSize:)`.
- It renders the mismatched tiles in creation order in one task, and the latest call wins through a cache-wide generation.
- A warm render of an 800x400 tile should take a few milliseconds, so tiles render on every `mouseDragged`. If a Mac cannot keep up, `RectDragTool` renders the live tile on mouseUp only, a one-line change.
- The transient effect being dragged is reconciled as the last effect. Its tile carries over unchanged on commit, because id, value and beneath are equal.

**Export.** `EditorModel.renderExport() async -> ScaledImage?` works in two steps:
1. `await tileCache.allTiles(for: document)` renders anything missing through the same actor, so export bytes equal preview bytes.
2. A `Task.detached(priority: .userInitiated)` calls `EditorFlattener.flatten(base:tiles:document:scale:) -> CGImage?`.

The flattener:
1. Creates `CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0, space: base.colorSpace ?? sRGB, bitmapInfo: premultipliedLast)`. If that colour space is refused, it converts the base to sRGB once.
2. Sets interpolation `.none` and draws the base.
3. Draws each tile at `ImageRects.bottomLeft(rect, imageHeight:)` on integral rects.
4. Flips the CTM to top-left and draws all drawings through the same `AnnotationDrawing.draw(_:in:scale:)` the canvas uses.
5. Calls `makeImage()`.
6. With a crop (`document.crop`), cuts the image to `CropGeometry.integralCrop` with `cropping(to:)`. The crop is last, so effects and drawings render on the whole capture first and a blur or redaction cut by the crop's edge has exactly the pixels it has uncropped.

It uses no NSGraphicsContext, which is MainActor. Pixels outside the effects equal the base byte for byte. Alpha survives, so window captures keep their transparent corners. A crop changes the pixel size that Save, Save As…, Copy and Upload write; the record's `pixelWidth` and `pixelHeight` and its thumbnail follow it through the existing coordinator paths. A solid redact over a transparent corner paints opaque pixels.

Encoding always uses `ImageEncoder.pngData(from:scale:)` with the capture's own scale (DPI 72 x scale), so a Retina edit stays 144 DPI. Copy also uses `Pasteboard.tiffData(of:scale:)`. The scale comes from `CaptureResult.scale` when the image was retained, or from `ImageEncoder.decode(_:).scale` when it was loaded from a file or a download.

**Redaction is tested end to end.** `RedactionExportTests` drives the real `RedactionRenderer` (no fake) through `EditorModel.renderExport()`, then `ImageEncoder.pngData`, then `ImageEncoder.decode`. The source is a 64x48 high-entropy sRGB image in which every pixel value is distinct from the redact fill. The tests assert, on the decoded PNG bytes:
1. Every pixel inside a redact region equals the fill, so no source value survives.
2. A blur placed over a redaction contains no pixel equal to the source at the same position inside the redaction.
3. Pixelate blocks are uniform, and at least one differs from the source.
4. A blur region differs from the source.
5. Pixels outside every effect equal the base, and the decoded scale is 2.

This is the automated counterpart of the manual 400% inspection in the checklist.

**Tools.** Tools are MainActor classes behind `protocol CanvasTool` (`cursor`, `mouseDown`, `mouseDragged`, `mouseUp`, `flagsChanged`). Each method takes `ToolInput { point: CGPoint; shift: Bool; option: Bool; clickCount: Int }` in image pixels. Tools talk only to `protocol CanvasEditing`, which EditorModel adopts and tests fake. Common rules:
- A tool commits exactly once per completed gesture, on mouseUp.
- The shape in progress lives in `transient` and is never undoable.
- Drags shorter than 2/zoom px in either dimension are discarded.
- `flagsChanged` re-applies Shift and Option mid-drag without mouse movement.

| Tool (letter) | Behaviour |
|---|---|
| **Select (V)** | `HitTester.topmost(in:at:tolerance:)` tests handles before bodies, and drawings front to back before effects front to back, so a blur under an arrow stays selectable. Tolerance is `8 / zoom` px. A drag moves the selection, and Shift locks the dominant axis. A handle drag resizes via `HitTester.resized(_:handle:to:square:)`: 8 handles for boxes, 2 endpoints for arrows. A click on empty space deselects. Delete removes the selection. Arrow keys nudge 1 px, or 10 px with Shift. Escape deselects. |
| **Redact (D)** | `RectDragTool(.redact)`. Shift squares and Option draws from the centre. The fill is `redactColor`, default black. It is listed first among the drawing tools because it is the only safe redaction. |
| **Pixelate (X)** | Default block `RedactionDefaults.block(points: 10, scale:, region:)`, with a floor of 6 pt x scale and capped at the region's shorter side. The options slider runs 6 to 32 pt. |
| **Blur (B)** | Default sigma 8 pt x scale, floor 4 pt x scale. The options slider runs 4 to 24 pt. |
| **Rectangle (R)** | A `ShapeBox` with `strokeColor` and `lineWidthPoints * scale`, stroked inset by half the line width so the stroke sits inside the rect. |
| **Arrow (A)** | `TwoPointTool(.arrow)`: tail at mouseDown, head at mouseUp. Shift snaps to 45 degrees. `ArrowGeometry.head(from:to:lineWidth:scale:)` gives a filled triangle with length `max(12 * scale, 4 * lineWidth)` and a 28 degree half-angle. The shaft stops at `ArrowGeometry.shaftEnd(from:to:lineWidth:scale:)` with round caps. |
| **Ellipse (E)** | `RectDragTool(.ellipse)`: a `ShapeBox` with `strokeColor` and `lineWidthPoints * scale`, stroked inside the dragged box. Shift makes a circle and Option draws from the centre. An ellipse no wider or taller than its line is filled so it still shows. Hit testing treats it as hollow: its body is the ring from the tolerance outside the outline to the line width plus the tolerance inside it. Eight handles; Shift keeps a circle on a corner handle. |
| **Line (L)** | `TwoPointTool(.line)`: a `Segment` from mouseDown to mouseUp with round caps and no head. Shift snaps to 45 degrees. Two endpoint handles. |
| **Pencil (P)** | `PencilTool(.pencil)`: every pointer sample is kept, and after each event the stroke is rebuilt from `StrokeSmoothing.decimated(_:minDistance:)` (spacing in points divided by the zoom) and drawn as a Catmull-Rom path (`StrokeSmoothing.catmullRom(_:)`) in `strokeColor` at `lineWidthPoints * scale`. One stroke is one commit on mouseUp, `Add Pencil`. A stroke whose points all stay within the tiny-drag distance of the first adds nothing, and Escape drops it. No handles: it moves, and its body is the smoothed path stroked at its width plus the tolerance. |
| **Highlighter (H)** | The same tool for a `Stroke` in the highlighter's own colour and width: yellow at alpha 0.45 (`EditorPalette.highlighterAlpha`) and 12 pt by default, neither persisted. It draws with the `multiply` blend in one stroke operation, so it can only darken what it covers (dark text stays readable) and a stroke that crosses itself is not darker there; two strokes that cross are. |
| **Text (T)** | `TextTool`: a click places a text box whose first line is centred on the click and starts editing in `strokeColor` at `textSizePoints` (20 pt by default, not persisted); a click on a committed text edits it again, and a drag places nothing. See "Phase 4b" below for the editing keys. |
| **Crop (C)** | `CropTool`: edits `EditorModel.cropDraft`, which starts as the applied crop or the whole capture and is cleared of the selection. A press on one of its eight handles resizes it (Shift squares a corner), a press inside moves it (Shift locks the axis), and a press outside draws a new rectangle (Shift squares, Option draws from the press point). `CropGeometry.clamped(_:to:)` keeps it inside the image, and it cannot shrink below the tiny-drag size. Return applies it as one `Crop` step and goes back to the tool used before Crop; Escape drops it and goes back; picking another tool applies it. |

A new shape is selected after creation. 4b added Ellipse (E), Line (L), Pencil (P), Highlighter (H), Text (T) and Crop (C). Each 4b tool added its case to `EditorTool` (the toolbar order comes from `EditorTool.toolbarOrder`), to `makeTool(for:)` in ToolFactory.swift, and to the tools group in EditorToolbar.swift.

**Palette and options.** The toolbar colour item shows the current colour as a filled circle. Its NSPopover (`.transient`) hosts `ColorPaletteView`: ten swatches (black, red, orange, yellow, green, teal, blue, purple, pink, white) plus `ColorPicker(supportsOpacity: false)`. Shapes use `strokeColor` (default red) and Redact uses `redactColor` (default black). The palette edits the colour of the active tool and of the selected annotation.

The options popover hosts `ToolOptionsView` with three controls:
- line width: 2, 3, 4, 6, 8 or 12 pt, also on keys 1 to 6, default 4 pt;
- blur radius;
- pixel block.

Changes apply live to the selection through a coalesced commit, so a slider drag is one undo step.

4b: with the Highlighter active, or Select with a highlighter selected, the colour popover edits the highlighter's own colour (which keeps alpha 0.45) and the width control edits its width; `strokeColor` is untouched. The colour also applies to the text being typed. Keys 1 to 6 set the text size to 12, 16, 20, 28, 40 or 56 pt while Text is the active tool, on the tool and on a selected text, and set line widths otherwise.

AppSettings persists five keys and adds no Settings tab: `editorStrokeColor` and `editorRedactColor` (RGBA as JSON Data), `editorLineWidthPoints` (4), `editorBlurRadiusPoints` (8) and `editorPixelBlockPoints` (10). They are read once into `EditorDefaults` when an editor opens.

**Undo.** EditorModel owns `let undoManager = UndoManager()` with `groupsByEvent = false`. UndoManager is MainActor-isolated in the 27 SDK, so no Sendable work is needed. `CanvasView.undoManager` and `windowWillReturnUndoManager(_:)` both return it, so `undo:` and `redo:` from the responder chain reach it.

The single write path is `commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String? = nil)`:
1. It wraps the registration in `beginUndoGrouping` and `endUndoGrouping`.
2. It registers a handler that re-commits the previous snapshot. That re-commit registers the inverse, which gives redo.
3. It calls `setActionName`, assigns `document` and calls `tileCache.reconcile`.

Coalescing works without timers. When `coalescingKey` equals the last commit's key, the document changes with no new registration, so a burst is one undo step. Arrow-key nudges use `"Nudge-<id>"` and a slider drag uses `"Blur Radius-<id>"`. The key is cleared by any other commit, by undo, by redo and by a selection change.

Selection, zoom, pan, tool and colour choice never enter the undo stack. `hasUnsavedChanges` is `document != savedDocument`, and also true while typed text would change the document or a crop draft would change the crop (4b). `markSaved()` runs after a successful Save, Save As… or Upload local write, and `window.isDocumentEdited` mirrors the flag. A text edit in progress (4b) uses its own UndoManager, described below. Step names: tools commit `Add <title>`, `Move <title>` and `Resize <title>` (`Add Text` for a text); the model uses `Delete`, `Move`, `Color`, `Line Width`, `Blur Radius` and `Block Size`, and 4b adds `Edit Text`, `Text Size`, `Crop`, `Duplicate <title>` and `Paste <title>`. While the Crop tool is active, ⌘Z and ⇧⌘Z that change the crop also move the open draft to the restored document's crop, or to the whole capture when it has none, so Return never re-applies a crop that was undone; a step that leaves the crop as it is (undoing a rectangle drawn before Crop opened) keeps the draft.

**Keyboard.**
- **Editor shortcuts.** The SwiftUI main menu of an LSUIElement app is never drawn, so editor shortcuts do not depend on it. `EditorWindow: NSWindow` overrides `performKeyEquivalent(with:)` and looks the event up in the pure table `EditorShortcut.match(characters:command:shift:option:control:isEditingText:)`. The key window sees key equivalents before the main menu, so nothing is handled twice. The 4a table:
  - ⌘S `saveDocument:`, ⇧⌘S `saveDocumentAs:`
  - ⌘C `copy:`, ⇧⌘C `copyImage:`
  - ⌘U `uploadDocument:`, ⌥⌘U `uploadDocumentAsNew:`
  - ⌘Z `undo:`, ⇧⌘Z `redo:`
  - ⌘W `performClose:`
  - ⌘0 `zoomToFit:` and ⌘1 `zoomToActualSize:` (natural point size)
  - ⌘= `zoomIn:` and ⌘- `zoomOut:` (factor 1.25 around the view centre)
  - ⌘A `selectAll:`

  In 4a, `copy:` reaches EditorWindowController, which copies the flattened image, so ⌘C and ⇧⌘C behave the same. In 4b, CanvasView implements `copy:` for a selected object and passes it up the responder chain when nothing is selected, so the table does not change for ⌘C. 4b adds ⌘V `paste:` and ⌘D `duplicate:` and updates the table test in the same task. ⌘X has no row in any phase: Phase 4 has no object cut (rejectedIdeas), so ⌘X always goes to the responder chain.
- **Object copy, paste and duplicate (4b).** `CanvasView.responds(to:)` answers `copy:` only with a selected annotation, `duplicate:` only with a selection and no drag running, and `paste:` only when the pasteboard holds an annotation and the Crop tool is not active, so a refused ⌘D or ⌘V finds no target and `EditorWindow` beeps. ⌘C with a selection writes the annotation as JSON under the private pasteboard type `io.tky.tidyshot.annotation` only (`AnnotationClip`: a format version, the annotation, and the capture's scale), with no notification and no image on the pasteboard. ⌘V places it with `AnnotationClip.placed`: scaled by the ratio of the two captures' scales so it keeps its size in points, centred in the visible image (the applied crop, else the whole image) when it would lie wholly outside it, and moved by the duplicate offset while an annotation identical to it apart from its id is already there. ⌘D, and an Option-drag with Select, make a copy 10 pt (`EditorModel.duplicateOffsetPoints`, times the scale) down and to the right of the selection, selected, as `Duplicate <title>`; a paste is `Paste <title>`. Option is read live during the drag: pressing it after the press turns the move into a copy, and releasing it moves the original instead.
- **Text editing bypass.** While a text annotation is being edited (`isEditingText`, 4b), `match` returns nil for the rows with `passesThroughWhileEditingText`: ⌘C, ⌘A, ⌘Z and ⇧⌘Z, plus ⌘V and ⌘D from 4b. Those keys then reach the NSTextView's own handling, as does ⌘X, which has no row: `EditorWindow` sends ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z and ⇧⌘Z to the first responder itself (`TextEditingChord`), so the text view and its private UndoManager get them whether or not the never-drawn main menu has an Edit menu. ⌘D matches nothing while text is typed. Save, Upload, Close and Zoom still match, and their controller actions first call `model.commitTextEditing()`.
- **Validation.** `NSApp.sendAction(_:to:from:)` does not consult `NSUserInterfaceValidations`. So on a match, EditorWindow:
  1. Resolves `NSApp.target(forAction:to: nil, from: self)`.
  2. If that target adopts NSUserInterfaceValidations, passes it a `ShortcutItem: NSObject, NSValidatedUserInterfaceItem` carrying the selector.
  3. When validation fails, beeps and consumes the event. Otherwise calls `NSApp.sendAction`.

  As a second guard, every action method on EditorWindowController (`saveDocument:`, `saveDocumentAs:`, `copyImage:`, `uploadDocument:`, `uploadDocumentAsNew:`) re-checks the available set and returns at once when its `EditorAction` is missing. The pure `EditorCommandGate.action(for:)` maps each selector to an `EditorAction`, and `EditorCommandGate.permits(_:available:)` decides. Both are tested. The coordinator applies a third check at write time (see Record state).
- **Unmodified keys.** These reach `CanvasView.keyDown` only while the canvas is first responder. `KeyRouting.action(characters:command:control:option:isEditingText:tool:)` maps tool letters and the digits 1 to 6 (`.lineWidth`, or `.textSize` when `tool` is Text). Space is checked first (`KeyRouting.isPanKey`) and never reaches `interpretKeyEvents`. Everything else goes to `interpretKeyEvents`:
  - Escape and ⌘. become `cancelOperation:`, which abandons the drag and then deselects; while the Crop tool is active it drops the draft and returns to the earlier tool. It never closes the window.
  - Return and Enter become `insertNewline:`, which applies the crop while the Crop tool is active and otherwise beeps.
  - Delete becomes `deleteBackward:` or `deleteForward:`.
  - The arrow keys become `moveLeft:` and its siblings, which nudge by `KeyRouting.nudge(dx:dy:shift:)`.
- **Pointer zoom and pan.** Pinch calls `magnify(with:)`, ⌘-scroll zooms around the cursor, and plain scroll pans. Zoom limits are `0.1 / captureScale ... 8 / captureScale`, and offsets snap to device pixels. Tooltips show each tool's letter. Holding Space and dragging pans too (4b): the press goes to the pan and the tool never sees it, the pan is unclamped like scrolling and stops the fit following window resizes, and it ends at mouseUp even when Space was released first. Space does nothing during a drag, and types a space while text is edited. Input to the tools is clamped to the applied crop's rect, since the cover hides the rest of the capture.

**Window.**
- **Shape.** `EditorWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations` runs one window per record. AppCoordinator holds the controllers in `editors: [UUID: EditorWindowController]`. The window is an `EditorWindow` with:
  - style mask `[.titled, .closable, .miniaturizable, .resizable]` and `toolbarStyle = .unified`;
  - normal level, managed collection behaviour plus `.fullScreenPrimary`, and `tabbingMode = .disallowed`;
  - `representedURL` set to the file when one exists, and `title` set to the file name or `Capture <time>`;
  - `subtitle` showing the status line from `EditorAvailability.status`, for example `Uploading…`, `Deleting…`, `The uploaded copy still shows the original. Upload to replace it.` or `This capture was deleted. Copy and Save As still work.`
- **Size and placement.** There is no frame autosave. `EditorWindowGeometry.initialContentSize(imagePixels:scale:chrome:visibleFrame:)` sizes the window to the image's natural point size plus chrome and a 24 pt inset. The size is at least 640x420, at least the toolbar's width, and at most 90% of the visible frame of the screen under the mouse. The toolbar's width comes from `EditorWindowGeometry.toolbarWidth(windowButtonsMaxX:titleWidth:toolSegments:buttons:prominentButtons:viewWidths:fixedSpaces:)`: the window buttons and the title (counted up to 96 pt, since a unified toolbar truncates its title first) are measured, the zoom pop-up has a fixed width, and the items AppKit draws itself use `EditorWindowGeometry.ToolbarMetrics`. `toolSegments` is `EditorTool.toolbarOrder.count`, one 36 pt segment per tool, so the toolbar with twelve tools, the widest title and (from 7c) the Background button is 1062 pt (4b without that button was 1016, the 4a toolbar 800), within 90% of a 1280 pt display; `toolbarWithEveryToolFitsASmallDisplay` pins the tool count and the width. `minimumContentWidth(toolbarWidth:)` (at least 640) becomes `contentMinSize.width` and the initial size's minimum, so the window never gets narrow enough for the overflow chevron. The transform starts at `CanvasTransform.fitting(imagePixelSize:in:inset: 24, captureScale:)`, never above natural size. Later editors are placed by `EditorWindowGeometry.cascaded(from:size:visibleFrame:)`, 22 pt down and to the right, clamped to the screen.
- **Showing.** `present()` calls `NSApplication.shared.activate(ignoringOtherApps: true)`, then `makeKeyAndOrderFront(nil)`, then `orderFrontRegardless()` if the app is still inactive. This is the codebase's proven idiom: a plain `activate()` is refused when called from the non-activating overlay.
- **Toolbar** (EditorToolbar.swift). `NSToolbar(identifier: "AnnotationEditor")`, `.iconOnly`, no customisation. The items, in order:
  - `.tools`: an `NSToolbarItem` whose view is a `ToolSegmentedControl` (an `NSSegmentedControl` with images, `.selectOne`, every segment 28 pt, and one tool tip rect per equal share of its bounds; changed 2026-10-22 because an `NSToolbarItemGroup` shows no sub-item tool tips and `setToolTip(_:forSegment:)` places tips by narrower segments than the macOS 26 toolbar draws), built from `EditorTool.toolbarOrder`: in 4b twelve tools, Select, Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text and Crop, each with a tool tip such as `Ellipse (E)`;
  - `.space`, `.color`, `.toolOptions`, `.background`, `.flexibleSpace`;
  - `.zoom`: a pop-up with Fit, 50 %, 100 %, 200 % and 400 %;
  - `.copyImage`: `doc.on.doc`, label `Copy`, tool tip `Copy the image (⌘C)`;
  - `.save`: `square.and.arrow.down`, label `Save`, tool tip `Save (⌘S)`;
  - `.upload`: `icloud.and.arrow.up`, label `Upload`, tool tip `Upload and copy the link (⌘U)`, `style = .prominent`.

  Copy, Save and Upload are plain `NSToolbarItem` buttons with no menus; Save As… (⇧⌘S) and Upload as New (⌥⌘U) are shortcuts only. Save keeps one label and tool tip and is enabled or disabled by validation. Liquid Glass comes free, so there are no custom backgrounds.
- **Closing.** `windowShouldClose(_:)` returns false while `hasUnsavedChanges` and runs `askToSaveBeforeClosing() async -> Bool` as an NSAlert sheet:
  - message: `Do you want to save the changes made to “<title>”?`
  - informative text: `Your changes will be lost if you don’t save them.`
  - buttons: Save, Cancel, and Don’t Save (⌘D). Save runs what ⌘S runs, so with no file to write over it opens the save panel. While Save is unavailable (uploading, deleting or deleted) the button reads `Save As…` and runs Save As…. `EditorSaveCommand.closeSheetButton(available:)` decides. The window closes only after the save succeeded; Cancel in the save panel keeps it open.

  Quitting does not call `windowShouldClose`. So `AppDelegate.applicationShouldTerminate(_:)` returns `.terminateLater` while any editor is dirty and calls `AppCoordinator.reviewEditorsBeforeQuit() async -> Bool`. On close, the controller tells the coordinator. The coordinator drops the registry entry and, when no editor is left, calls `RedactionRenderer.shared.clearCaches()`.
- **Record state.** One coordinator helper, `pushEditorState(for id: UUID)`, calls `editors[id]?.recordDidChange(history.record(id: id), saveFolder: saveLocation.currentURL, isDeleting: deletingIDs.contains(id))`. A nil record means deleted or pruned. These call it:
  - `refreshOverlay(for:)`, so every upload progress, success, failure and retry reaches the editor;
  - `removeRecord(id:)`;
  - `removeFiles(ofPruned:)`, for each pruned record, because retention pruning goes through `didPrune` and not through `removeRecord`;
  - `deleteCapture(recordID:)`, right after `deletingIDs.insert` (AppCoordinator.swift:538) and again from its `defer` after `deletingIDs.remove`. While the delete alert, `cancelUpload`, `deleteObjects` and the second alert are pending, `EditorAvailability.actions(record:saveFolder:isDeleting: true)` leaves only Copy and Save As…;
  - `editorUpload`, after its own `history.update` sets `.uploading(0)`. `startUpload` calls `refreshOverlay` only for a record that is not already uploading (AppCoordinator.swift:385-388), so without this the editor would learn of the upload only at the first progress event.

  Save-folder changes are pushed too. While any editor is open, the coordinator observes `saveLocation.currentURL` (SaveLocation is `@Observable`). It uses the `withObservationTracking { } onChange: { Task { @MainActor in … } }` idiom from StatusMenuController and re-registers on each change. A change calls `pushEditorState` for every open editor, so Save availability and the subtitle follow a folder chosen in Settings. Safety does not depend on this push: `EditorSaveTarget.plan` is recomputed from the current record and folder at write time.

  The same set drives the toolbar items and the shortcut gate. `editorSave` and `editorUpload` also re-check, at write time and on the coordinator side, `EditorAvailability.refusal(for:record:saveFolder:isDeleting:)`. They use `history.record(id:)` and `deletingIDs.contains(id)` read at that moment. A non-nil reason posts `notifyError(reason, title: "Not saved")` (or `"Not uploaded"`) and writes nothing. A Save racing a delete therefore never recreates a pending or thumbnail file for a removed record.

**Opening from the overlay.** `QuickAccessController.Actions` gains `annotate: (UUID) -> Void`, and `QuickAccessModel` gains `onAnnotate`. `QuickAccessView` gets a `pencil.tip.crop.circle` plain button (help `Annotate`) at the top of the right column, above Close and Delete. Column spacing becomes 8 and `QuickAccessView.size` stays 340x104. `showOverlay` binds `annotate` to `openEditor(recordID:)`, and Annotate stays enabled while the upload runs.

In `save(_:)`, when the overlay is shown, the coordinator keeps `latestCapture: (id: UUID, image: ScaledImage)?`. The overlay's NSImage already wraps the same CGImage, so this costs no memory. It is cleared by three events: the new `QuickAccessController.onDidClose: ((UUID) -> Void)?`, the next capture, and `removeRecord`.

`openEditor(recordID:)` works in five steps:
1. If an editor is already open for the record, it brings that editor forward with `present()`.
2. Otherwise it asks `EditorInput.source(for:retainedID:saveFolder:)`.
3. `.retained` takes the in-memory image at once. This covers an upload-only capture whose pending file is gone after upload, and a capture that is still uploading.
4. `.pendingFile`, `.saveFolderFile` and `.download` go through the existing `imageData(of:)`: a detached scoped or pending read, falling back to a signed GET. `ImageEncoder.decode` then runs in a detached task to recover the scale. `.unavailable(reason)` posts `notifyError(reason, title: "Could not open the capture")`.
5. It builds the EditorModel and the controller, then closes the overlay. The editor is now the record's surface, and the record stays in Recent Captures.

The image source per record kind, from the overlay:
- **Save-folder file** (Save and Upload modes): the retained image, falling back to a scoped read.
- **Upload-only, pending or failed:** the retained image, falling back to the pending file.
- **Upload-only, already uploaded** (`fileURL` nil): the retained image, falling back to a signed GET from `objectLocation` + `uploadedKey`.
- **Pre-Phase-3 uploaded record:** the scoped read. Without a file it is `.unavailable`.

**Annotate from Recent Captures.** Each Recent Captures row gains a fourth icon button, Annotate (`pencil.tip.crop.circle`), before Copy URL. `RecentCaptureActions` gains `annotate: (UUID) -> Void`, which runs through `afterMenusClose` like the other row actions, so the window never opens inside menu tracking. It calls the same `openEditor(recordID:)`; with no retained image the loader reads the file or downloads the object. The button is disabled when `EditorInput.source` would be `.unavailable` (a pre-Phase-3 record with no file). This gives an entry point with Show overlay off, and a way back to an upload-only record whose replace failed (see Outcome below).

**One local-edit path.** Save and the local write before an Upload both go through `applyLocalEdit(recordID:png:image:) async -> Bool`. That function:
1. Re-checks `EditorAvailability.refusal` on the current record.
2. Writes the file for the target `EditorSaveTarget.plan(for:saveFolder:)` picks, using the current record and folder.
3. Sets `pixelWidth`/`pixelHeight` and `editedAt = now` with `history.update(id:)`.
4. Sets `uploadIsStale = true` when the record has an `uploadedURL` or a `priorUpload`.
5. Replaces the thumbnail and calls `thumbnailProvider.forget(id)`.
6. Applies the clipboard rule.
7. Calls `pushEditorState(for:)`.

The editor then calls `markSaved()`. Upload therefore implies Save over whenever a save target exists (decided 2026-10-20).

**Save (⌘S).** `EditorSaveTarget.plan(for:saveFolder:)` picks the target:
- `.saveFolderFile(url, folder:)` when the file is in the current save folder, checked with `SaveLocation.contains(_:inFolder:)`. The write is the new `nonisolated static SaveLocation.overwriteScoped(_ data: Data, at fileURL: URL, folder: URL) throws`. It is atomic, runs under the folder's scope in a detached task, and throws `CocoaError(.fileWriteNoPermission)` for a file outside the folder.
- `.pendingFile(url)` for a temporary file. The write is `pendingFiles.write(png, id:, ext: "png")`, which replaces `<id>.png` in place, so a later retry uploads the edited bytes.
- `.unavailable(reason)` for a record with no local file, a file outside the current folder, or no folder. ⌘S then runs Save As… (below) instead of writing over anything, and the subtitle gives the reason. `EditorSaveCommand.forSave(record:saveFolder:)` makes this choice in the controller from the pushed record and folder: `.writeOver` or `.saveAs` (also for a deleted record). The coordinator plans again at write time; a folder changed in between posts `Not saved` with the reason.

Save and Upload are disabled while the record is uploading or being deleted, and for a deleted record; Save As… stays available. Save never touches the network. On an uploaded record, `uploadIsStale` drives the subtitle `The uploaded copy still shows the original. Upload to replace it.` A failed write posts `notifyError(..., title: "Not saved")` and puts the edited image on the clipboard, so an edit is never dropped.

**Clipboard rule (secrets).** `save(_:)` copies the original image when `copyImageNow` is true (AppCoordinator.swift:171-183). That happens in three cases:
- Save mode with "Copy image to clipboard" on (the default);
- Upload or Upload-only mode with "Also copy image";
- an upload action with no destination configured, where the image goes to the clipboard instead of a URL.

The `keepOnClipboard` failure paths also copy it, but they return before a record exists, so no editor can open for that image. After a redaction, the original would stay on the clipboard. To prevent that:
- `Pasteboard.copy` now returns the pasteboard's `changeCount`.
- The coordinator keeps `clipboardOwner: (recordID: UUID, changeCount: Int)?`. `save(_:)` sets it whenever `copyImageNow` is true, and the editor's Copy also sets it.
- After a successful local edit or Save As…, the coordinator replaces the clipboard with the edited PNG and TIFF when `EditorClipboard.shouldReplace(owner:recordID:currentChangeCount:)` holds. That means the clipboard still holds exactly what TidyShot put there for this record. Anything the user copied since is left alone.
- An Upload's `.uploaded` handler then copies the URL as the last write, as it does today.

**Save As… (⇧⌘S, `saveDocumentAs:`).** Replaced Save Copy after the 4a build. It opens an `NSSavePanel` as a sheet on the editor window, with PNG as the only allowed content type. `EditorNaming.saveAsSuggestion(for:saveFolder:namer:currentCounter:)` gives the panel's name and folder:
- the record's file name when it has a file in the save folder; otherwise (no file, a pending `<id>.png`, or no record) the name `FileNamer` gives with the current template, plus `.png`. `{counter}` uses `AppSettings.currentCounter` and draws nothing, so the next capture's number is unchanged;
- the save folder as the directory when one is set.

The panel opens before the document is flattened, so the image written is the one confirmed. On OK, `editorSaveAs(image:to:)` encodes with `ImageEncoder.pngData(from:scale:)` (DPI 72 x scale) and writes the PNG to the chosen URL atomically, in a detached task. The URL is user-selected, so the sandbox grants access, and no bookmark is kept. No history record is made, nothing uploads, and the record and its thumbnail are untouched. The clipboard rule applies as after Save: when `EditorClipboard.shouldReplace(owner:recordID:currentChangeCount:)` holds, the clipboard gets the edited PNG and TIFF and `clipboardOwner` moves to the new change count (decided by the controller, 2026-10-20). On success the editor calls `markSaved()`, and when Show notification is on a `Saved` notification names the file; clicking it reveals the file, as for `notifySaved(fileURL:)`. A failed write posts `notifyError(<error>, title: "Not saved")` and the editor stays dirty. Cancel does nothing. When the chosen URL is the record's own file (compared standardized) and ⌘S could write over it now (`EditorSaveTarget.saveAsWritesOverOwnFile(_:record:saveFolder:isDeleting:)`), the coordinator runs Save instead, so the record, its thumbnail and the stale flag follow. Save As… is never refused, so it also works while the record uploads, is deleted or is gone.

`persist(png:image:action:destination:alreadyOnClipboard:)` remains the capture save path behind `save(_:)`; the Save Copy options (`baseName`, `playsSound`) went with it.

**Copy (⌘C, ⇧⌘C).** `ImageEncoder.pngData` and `Pasteboard.tiffData` run detached. Then `Pasteboard.copy(pngData:tiffData:)` runs on the main actor and the coordinator records `clipboardOwner`. An `Image copied` notification is posted when `settings.showNotification` is on. The window stays open.

**Upload (⌘U) and Upload as New (⌥⌘U).**
- **Prior upload, persisted.** `CaptureRecord.priorUpload: PriorUpload?` (decodeIfPresent, default nil) holds `PriorUpload { url: URL; key: String; location: ObjectLocation; isReplace: Bool }`.
  - It is set whenever the editor uploads a record that has a link, in the same `history.update` that sets `.uploading(0)`. It is cleared on `.uploaded` and on a handled failure.
  - `uploadedURL` and `uploadedKey` stay computed from `uploadState` only. The new `linkURL` is `uploadedURL ?? priorUpload?.url`. `RecentCaptureFormatting.canCopyLink` and the coordinator methods `AppCoordinator.copyLink(recordID:)` and `copyLinkOrFile(recordID:)` (AppCoordinator.swift:443-458) use it.
  - A crash or quit mid-upload goes through `HistoryStore.load`, which turns `.uploading` into `.failed("Upload was interrupted.")`. `priorUpload` survives on disk, so the shared link stays copyable.
  - `CaptureDeletion.objects(for:)` lists the prior key at its own location, so Delete removes it. `sharedKeys` and `deleteOrphanedObject` see it too.
- **Plan.** `EditorUploadPlan.plan(record:currentLocation:others:asNew:)` takes the record's link from `uploadedKey` with `objectLocation`, or else from `priorUpload` (key and location). It returns one of:
  - `.refuse(reason)` while the record is uploading.
  - `.replace(key:)` when all four hold: a link exists; its location equals `ObjectLocation(config: destination.config)`; `CaptureDeletion.sharedKeys([key], at:, with: others)` is empty; and `asNew` is false.
  - `.newObject(supersede: ObjectRef?, notice: String?)` otherwise:
    - Never uploaded: a plain first upload.
    - `asNew`: supersede the old key.
    - Destination changed: supersede the old key at its own location, with the notice `The destination changed, so this uploads as a new link.`
    - Key shared with another capture: no supersede, with the notice `Another capture shares this link, so this uploads as a new link.`
    - Pre-Phase-3 record: no supersede, with the notice `The earlier upload stays in the bucket.`
- **Retry.** `retry(recordID:destination:)` asks `EditorUploadPlan.retryPolicy(record:currentLocation:others:)`, which returns one of:
  - `.fixed(key)` for a `priorUpload` with `isReplace` whose location still matches and whose key is unshared. An interrupted or failed replace is re-PUT to the same key, so no new key is minted.
  - `.template(supersede: ObjectRef?)` otherwise. A replace whose destination has since changed supersedes the old key.
- **Local write first.** Before any upload, the coordinator runs `applyLocalEdit`, so the file equals the object. For a record with no local file, it writes `pending/<id>.png` and sets `fileURL` and `fileIsTemporary = true`. Retry and Delete then see the file, and `handle(.uploaded)` removes it as today. A save-folder file outside the current folder, or one with no folder set, is handled the same way (`EditorSaveTarget.uploadWrite` gives `.newPendingFile` for every `.unavailable` plan, review fix 2026-10-20): the edit goes to `pending/<id>.png`, the record switches to it in the same `history.update`, and the original file stays where it is, no longer referenced by the record. From then on it behaves like an upload-only capture, so Retry reads the edited bytes and never uploads the unredacted original.
- **Starting.** `editorUpload` performs these steps:
  1. `EditorUploadPlan.startingUpload(_:plan:)` sets `uploadState = .uploading(0)`, `priorUpload` and `supersededObjects` in one `history.update`.
  2. It inserts the id into `uploadingIDs` through `startUpload`.
  3. It calls `refreshOverlay(for:)` itself, which also pushes the editor state, so the overlay and the editor show `Uploading…` at once.
- **Replace.** Replace sets `priorUpload` (isReplace true) and calls `startUpload(recordID:data:destination:fixedKey: key)`.
  - `UploadJob` gains `enum KeyPolicy: Sendable, Equatable { case template(TemplateContext); case fixed(String) }`.
  - The existing `init(...naming:)` keeps mapping to `.template`, and a new `init(id:data:contentType:fileExtension:fixedKey:cacheControl:)` is added.
  - For `.fixed`, `UploadQueue.process(_:)` skips `reserveKey`, records the key in `reservedKeys` so a cancel reports it, re-PUTs the same key on retry, and draws no `{counter}`.
- **Why skipping HEAD is safe.** HEAD-before-PUT exists to avoid overwriting another object. A fixed key is only ever this record's own key at its own location, and the shared-key rule has already excluded every other record that points at it. A HEAD would find the record's own object and wrongly steer away from it. Template jobs are unchanged, and all 16 UploadQueueTests stay green.
- **Cache-Control.** Fixed-key PUTs send `Cache-Control: no-cache` as a signed header. `Destination.upload` gains a `cacheControl: String?` parameter, and a protocol extension keeps the old four-argument call. `handle(.uploaded)` re-copies the URL, which is unchanged unless the Public URL template was edited.
- **Caches keep what they already served.** A replace does not purge CloudFront or any other cache. Normal uploads send no Cache-Control, so a CDN that fetched the link before the replace serves the original until its own TTL expires, and a browser that opened it may too; a versioned bucket also keeps the old bytes as a prior version. Redacting before the link is first opened (before it is pasted anywhere that unfurls it) leaves nothing cached. Upload as New deletes the old object at the origin, which stops new edge fetches, but it does not purge an edge copy either. The README and the 4a checklist say this, and the first replace in a session posts the notification `Replaced. Copies opened before now may stay cached for a while.`
- **New object.** Before `startUpload`, the coordinator appends the old `ObjectRef { key; location }` to `CaptureRecord.supersededObjects: [ObjectRef]` (decodeIfPresent, default []) and sets `priorUpload` (isReplace false). After `.uploaded`, `deleteSupersededObjects(of:)` deletes each ref at its own location. It skips keys that `sharedKeys` reports and drops the refs that delete successfully. Failures stay on the record, and `deleteCapture` removes them later through `CaptureDeletion.objects(for:)`. That function lists, grouped by location:
  - the uploaded key and the pending key at `objectLocation`;
  - the prior upload at its location;
  - the superseded refs.

  `ObjectLocation` becomes Hashable.
- **Outcome.** The pure functions `EditorUploadPlan.applyingSuccess(to:)` and `applyingFailure(to:message:)` decide record state.
  - On `.uploaded`, `priorUpload` and `uploadIsStale` are cleared.
  - On `.failed` with a `priorUpload`, the record returns to `.uploaded(url, key)` at the prior location. It keeps `uploadIsStale = true`, drops the superseded ref it added (the old object is live again) and clears `priorUpload`. The coordinator then notifies `Upload failed. The link still shows the earlier image.` instead of calling `markFailed`.
  - On a failed replace for an upload-only record whose file was gone, the restored record keeps `fileURL = pending/<id>.png` with `fileIsTemporary = true`. That file holds the edited bytes, and the subtitle says the link still shows the original. `HistoryStore.pruned` never drops a record with `keepsUnuploadedEdit` (`fileIsTemporary && fileURL != nil && uploadIsStale`). Annotate on its Recent Captures row reopens it, a later Upload replaces the object, and `handle(.uploaded)` removes the file.
  - A record with no `priorUpload` fails as today.
- **Closing.** `editorUpload` returns `EditorUploadOutcome { wroteLocally; enqueued }`. The editor marks itself saved when `wroteLocally` and nothing was edited meanwhile, and closes the window, without the unsaved-changes sheet, when `closesWindow(documentUnchanged:)` holds: the job was enqueued (every enqueued upload has written the edit locally first) and nothing was edited while the call ran; in that last case the editor beeps and stays open. The link then reaches the clipboard through `.uploaded`. A refused upload (not configured, busy, deleted, or refused by the plan) leaves the window open, and its notification says why. A later failure posts the usual failure notification; the record keeps the edited local or pending file, and Annotate on its Recent Captures row reopens it. Upload as New (⌥⌘U) closes the same way.
- **Lane.** Every editor upload goes through the live lane, so cancel, progress, `uploadingIDs`, Delete and the menu bar icon keep working. The URL copy on `.uploaded` is always the last clipboard write.

**Thumbnails after an edit.** An edited thumbnail gets a new name, `ThumbnailStore.fileName(for:editedAt:)` = `<UUID>-<milliseconds>.png`, written by the new `ThumbnailStore.write(_:fileName:)`. The previous file is removed. `RecentCaptureRow` reloads on `.task(id: record.thumbnailFileName)`, so rows refresh without further work.

Neither older writer can clobber an edited thumbnail:
- The capture-time `makeThumbnail` and the legacy `ThumbnailProvider` path only ever write `<UUID>.png`.
- A late `makeThumbnail` checks `record.editedAt == nil` before naming its file on the record, and otherwise deletes the file.
- ThumbnailProvider needs no change: its `forget` bumps the generation, so a late legacy write is discarded.

`CaptureRecord.editedAt: Date?` and `uploadIsStale: Bool` (both decodeIfPresent) drive the subtitle note.

**Phase 4b (built).** The tools are in the Tools table; what else 4b added:
- Rendering: Pencil and Highlighter share `AnnotationDrawing.drawStroke`, and the canvas and the export draw every 4b drawing through the same routine as the 4a ones. The highlighter's multiply needs real pixels under it, which the canvas backdrop and the flattener supply.
- Text: an NSTextView (TextKit 2, plain text, no substitutions) subview of CanvasView, framed by `TextLayout.frame(for:)` and the transform.
  - Return, Enter and Tab commit; Shift-Return and ⌥Return insert a newline; Escape and ⌘. cancel (a new text disappears, a re-edit keeps the earlier string). A click elsewhere on the canvas commits and does nothing else. An empty new text adds nothing; a re-edit cleared to nothing is deleted. Trailing newlines are dropped.
  - A double-click on a text with Select, or a click on one with Text, edits it again in place (the annotation keeps its id and its place in the creation order).
  - Its delegate's `undoManager(for:)` returns a private UndoManager for the edit, so typing never registers into the editor's `groupsByEvent = false` manager. Committing the text is one editor commit (`Add Text`, or `Edit Text` for a re-edit), and the private manager is then emptied and discarded.
  - `isEditingText` turns off tool letters, the digit keys, Space-pan and the pass-through chords in EditorShortcut. Save, Save As…, Copy Image, Upload, Close and the zoom commands first call `model.commitTextEditing()`. Picking another tool commits.
  - Committed text is drawn with CoreText on the bare CGContext, with a flipped text matrix, at the same frame TextKit lays out.
- Crop: `document.crop` with 8 handles, a dim mask and a W × H readout, as in the Tools table. The crop is undoable, is applied last at export, and updates the pixel size on Save, Save As…, Copy and Upload. An applied crop is covered, not removed: annotations outside it stay in the document, but VoiceOver lists, and ⌘A selects, only an annotation that reaches into it. A press in the covered area (`CropGeometry.press`) is not clamped onto the crop's edge: Select deselects and ignores it unless it lands on a handle of the selected annotation, Text ignores it, and the drawing tools start at the edge. Drags and releases are clamped to the edge.
- Duplicate, object copy and paste, Space-drag pan: see Keyboard.
- Canvas accessibility: the canvas is an `AXLayoutArea` labelled `Annotation canvas` (`CanvasAccessibility.canvasLabel`) with one `AnnotationAccessibilityElement` (`AXLayoutItem`) per annotation, in painting order (every effect, then every drawing, each in creation order). The label is the kind plus a number counted per kind (`Redact 1`, `Arrow 2`), a text's value is its string, the frame is the annotation's painted bounds at the current zoom and pan, and AXPress selects it (not while a drag runs or the Crop tool is active). Elements are reused by id so VoiceOver focus survives a refresh, and layout and selection changes are posted when the document or the selection changes.
- A 4b checklist (`docs/testing/phase-4b-manual-checklist.md`), a README section and a totals check.

**Phase 4c (P2).**
- Spotlight and Counter. Built in Phase 4c (2.12).
- The `.tidyshot` project package. It is local only and never uploaded, and a warning says it keeps the unredacted original. Still later.
- The after-capture open-editor option. Still later.

### 2.7 Optimise images with Clop before upload (2026-10-20, settled 2026-10-21)

**Request.** Dropshare's Images setting "Optimize images with Clop" shrinks images before they upload. Its caption reads "Clop is an image optimizer that greatly reduces file size." TidyShot gets the same option for people who have [Clop](https://lowtechguys.com/clop) installed. Tim owns the paid version.

**Integration.** Clop listens on a CFMessagePort named `<Clop bundle id>.optimisationService`:
- `com.lowtechguys.Clop.optimisationService` for the direct build;
- `com.lowtechguys.Clop-setapp.optimisationService` for the Setapp build.

[ClopSDK](https://github.com/FuzzyIdeas/ClopSDK) (MIT) is a thin client for that port. TidyShot vendors a cut-down copy of it as `TidyShot/Upload/ClopClient.swift` and does not add the package; see answer 6.

The Clop app itself is GPLv3. TidyShot only talks to it over the port and never reads or copies its code, which keeps decision 7.

**Answers (probed 2026-10-21 on macOS 27.0.1, Clop 3.4.3 Pro, with sandboxed ad-hoc probe apps).**

1. **Sandbox: a new entitlement is needed.**
   - **Evidence.** With TidyShot's four entitlements, the lookup fails. `CFMessagePortCreateRemote` returns nil, and the log shows `launchd: denied lookup: name = com.lowtechguys.Clop.optimisationService ... error = 159: Sandbox restriction`. With `com.apple.security.temporary-exception.mach-lookup.global-name` the request succeeds.
   - **Entitlement.** TidyShot adds that entitlement for `com.lowtechguys.Clop.optimisationService` and `com.lowtechguys.Clop-setapp.optimisationService`. This amends the "no new entitlements" constraint.
   - **Mac App Store.** A temporary exception needs App Review approval. It does not affect the Developer ID or ad-hoc builds. A future Mac App Store build would have to justify it or drop the feature.
2. **File access: no prompt.**
   - **Evidence.** Clop, which is not sandboxed and has no Full Disk Access, read and rewrote PNGs in the probe's container (`tmp` and Application Support) without a prompt or a failure. The tccd log shows no `SystemPolicyAppData` request for Clop.
   - **Fallback, untested signing.** This was tested with ad-hoc containers. If TidyShot is ever team-signed and macOS then prompts, the fallback is a temporary file in the save folder through the bookmark. Clop read `~/Downloads` without a prompt in the probe.
3. **Output path: TidyShot passes none.**
   - **Default.** With no output path, Clop rewrites the file in place and keeps its modification date. The response `path` equals the input.
   - **`output` parameter.** The SDK's `output` is an extensionless path template: Clop appends the extension, so `x.png` becomes `x.png.png`, and `%f` stands for the input's base name. TidyShot does not use it. It writes a throwaway copy and lets Clop rewrite it.
   - **Clop's cache.** Clop also keeps the original and the result in `~/Library/Caches/Clop/backups/` and `images/`, and TidyShot cannot remove them (see the caption).
4. **DPI and format: 144 DPI survives; PNGs stay PNG.**
   - **DPI.** Clop 3.4.3 dropped the `pHYs` and `sRGB` chunks but kept `eXIf`, which carries XResolution 144. Clop 3.6.2 (recorded 2026-10-21, the version the test fixtures come from) keeps `pHYs`. Either way ImageIO, `NSImage` and `ImageEncoder.decode` still read 144 DPI and scale 2.
   - **Format.** The result is a 256-colour indexed PNG, which is lossy.
   - **Conversion.** Under Tim's settings PNG is not converted to another format. If a user's Clop settings convert PNG (the response then has a different `path` and a `convertedFrom`), TidyShot uploads its original PNG.
5. **Licensing: works with Pro; the SDK does not say.**
   - Requests work with Tim's Pro licence. The SDK reports nothing about licensing.
   - Clop's site caps on-demand and automation use at 5 per session on the free tier. TidyShot treats any throw, timeout or bad reply as "upload the original", so a free user just gets unoptimised uploads after the cap.
6. **Dependency: vendored, so KeyboardShortcuts stays the only package.**
   - **Why not the package.** ClopSDK 1.1.2 (swift-tools 5.9, macOS 13) only compiles under TidyShot's Swift 6 settings with `@preconcurrency import`, because `OptimisationResponse` is not `Sendable`. It also blocks for up to 600 s, launches Clop if it is not running, can run a Spotlight query over `/`, and keeps mutable globals.
   - **The vendored client.** It is about 70 lines: the two `Codable` structs with ClopSDK's field names, plus one `CFMessagePortSendRequest`, all `nonisolated` and `Sendable`. It compiles cleanly under TidyShot's settings, and the sandboxed probe reached Clop with it.
   - **Licence notice.** The file keeps the MIT notice in its header, and a new `ThirdPartyNotices.md` at the repo root carries the full ClopSDK licence text.

**Measurements** (sandboxed, Tim's Clop settings). Times run from request to reply:

| Image | Before | After | Reduction | Time |
|---|---|---|---|---|
| 3094x2352 screenshot-like PNG | 1.30 MB | 342 KB | 73.6% | 0.63–0.76 s |
| Real 2x screenshot, 3094x2352 crop | 702 KB | 247 KB | 64.9% | 0.65 s |
| Real 5120x2880 screenshot | 2.81 MB | 757 KB | 73.1% | 1.06 s |
| 3094x16000 tall | 9.06 MB | 2.42 MB | 73.3% | 2.26–2.35 s |
| Already optimised | — | unchanged | 0% | 0.01 s |

**Behaviour.**
- **Setting.** The General tab has a `Section("Images")` between its first section and "URL commands" (moved from the Upload tab after Tim's test, 2026-10-21):
  - **Control.** `Toggle("Optimize images with Clop", isOn: $settings.optimiseWithClop)`.
  - **Caption.** "Clop is an image optimizer that greatly reduces file size. Clop keeps its own copy of each image it optimizes."
  - **Storage.** `AppSettings.optimiseWithClop` (key `optimiseWithClop`, default `false`). It is an app setting, not part of the destination draft, so it takes effect without Save.
  - **Clop not installed.** "Installed" means `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` finds `com.lowtechguys.Clop` or `com.lowtechguys.Clop-setapp`. Otherwise the toggle is disabled, and the caption is followed by `Link("Get Clop", destination: URL(string: "https://lowtechguys.com/clop")!)`.
- **When.** `AppCoordinator.startUpload(recordID:data:destination:fixedKey:)` is the one funnel for every upload: a fresh capture, upload-only, editor Upload, the same-key replace, Upload as New, and Retry of any of them. Inside its `Task`, before the `UploadJob` is built, it calls `await clopOptimiser.optimisedPNG(data)` when `settings.optimiseWithClop` is on, and uploads the bytes it returns. The record stays `.uploading(fraction: 0)` meanwhile. The save-folder file, the upload-only `pending/<id>.png` and the editor's saved file all stay as captured, so a Retry re-optimises from the original.
- **Running check.** TidyShot never launches Clop. If neither bundle id is running (`NSRunningApplication.runningApplications(withBundleIdentifier:)`), it uploads the original.
- **Never lose a capture.** TidyShot uploads the original bytes, logs one `NSLog` line (`Clop: <reason>, uploading the original`) and posts no error when any of these happen:
  - Clop is not running.
  - The request throws or times out (send 2 s, receive 30 s).
  - The reply is empty or undecodable.
  - The response `path` is not the file TidyShot sent (a conversion), or `convertedFrom` is set.
  - The result is not a decodable PNG with the same pixel size.
  - The result is not smaller.
- **Format.** The upload is always PNG (`image/png`, `.png` key), as decision 5 says. The format-following branch from the first draft of this section is dropped.

**Types** (all in `TidyShot/Upload/`):
- **`ClopClient.swift`** (vendored, MIT header "Adapted from ClopSDK (https://github.com/FuzzyIdeas/ClopSDK), MIT License, Copyright (c) 2023 The low-tech guys. See ThirdPartyNotices.md."):
  - `nonisolated struct ClopRequest: Codable, Sendable`. Fields in ClopSDK's order and names: `id`, `urls`, `originalUrls = [:]`, `size: CropSize?`, `downscaleFactor`, `changePlaybackSpeedFactor`, `hideFloatingResult`, `copyToClipboard`, `aggressiveOptimisation`, `source = "sdk"`, `output`, `removeAudio`.
  - `nonisolated struct ClopResponse: Codable, Sendable, Equatable`, with `path`, `forURL`, `convertedFrom`, `oldBytes`, `newBytes`, `oldWidthHeight`, `newWidthHeight`.
  - `nonisolated enum ClopClientError: Error, Equatable`, with cases `portUnavailable`, `sendFailed(Int32)` and `badReply`.
  - `nonisolated struct ClopClient: Sendable`, with:
    - `static func portName(bundleID: String) -> String`, which returns `"\(bundleID).optimisationService"`;
    - `init(bundleID:sendTimeout: 2, receiveTimeout: 30)`;
    - `func optimise(_ url: URL) throws -> ClopResponse`, which blocks and is only called off the main actor.
  - The request sends `hideFloatingResult: true`, `copyToClipboard: false` and `aggressiveOptimisation: false`.
- **`ClopOptimiser.swift`:**
  - `nonisolated struct ClopOptimiser: Sendable`, initialised with `workDirectory: URL` (the container's `tmp/Clop`) and `transport: @Sendable (URL) throws -> ClopResponse`.
  - `func optimisedPNG(_ data: Data) async -> ClopOutcome`. It:
    1. writes `<workDirectory>/<UUID>.png`;
    2. runs the transport on one private serial `DispatchQueue` (`io.tky.tidyshot.clop`, bridged with `withCheckedContinuation`), so requests reach Clop one at a time and never block a cooperative-pool thread;
    3. validates the result;
    4. reads it back;
    5. deletes the file in a `defer`.
  - `nonisolated enum ClopOutcome: Equatable` has `.optimised(Data, oldBytes: Int, newBytes: Int)` and `.original(ClopSkipReason)`.
  - `ClopSkipReason` has `.notRunning`, `.failed(String)`, `.converted`, `.notSmaller` and `.invalidResult`.
  - The coordinator builds it with a transport that wraps `ClopClient(bundleID:)` for the running Clop's bundle id. If no Clop is running, it returns `.original(.notRunning)` without writing a file.

**Entitlement change** (`project.yml`, TidyShot target `entitlements.properties`):
```yaml
        com.apple.security.temporary-exception.mach-lookup.global-name:
          - com.lowtechguys.Clop.optimisationService
          - com.lowtechguys.Clop-setapp.optimisationService
```
Update the Distribution row of section 4 to list it.

**Tests** (Swift Testing, no live Clop):
- **`ClopClientTests`:**
  - `ClopRequest` encodes the keys ClopSDK's `OptimisationRequest` uses: `urls` as `file://` strings, `originalUrls` as `[]`, `source == "sdk"`, `hideFloatingResult == true`, `copyToClipboard == false`, and nil optionals omitted.
  - `ClopResponse` decodes the reply recorded from Clop 3.6.2, both with and without `newWidthHeight`; the second is the already-optimised case.
  - `portName(bundleID:)` gives both port names.
- **`ClopOptimiserTests`** (fake transport):
  - A smaller valid PNG at the same path returns `.optimised` with its bytes.
  - The fake sees a file holding exactly the input bytes.
  - The work file is gone afterwards in every case.
  - A throwing transport returns `.original(.failed)`.
  - `newBytes >= oldBytes` returns `.original(.notSmaller)`.
  - A response with another `path` or `convertedFrom` returns `.original(.converted)`.
  - Non-PNG or wrong-size result bytes return `.original(.invalidResult)`.
  - An optimised PNG carrying only `eXIf` resolution, with no `pHYs`, still gives `ImageEncoder.decode(...).scale == 2`. The fixture is a 2x PNG with its `pHYs` chunk removed.
- **`AppSettingsTests`:** `optimiseWithClop` defaults to false and persists.
- **Manual checklist (Phase 7):**
  - With Clop running, an area capture uploads a smaller object, and the downloaded object reports 144 DPI (`sips -g dpiWidth`).
  - A scrolling capture uploads optimised.
  - Editor Upload, replace, Upload as New and Retry are each optimised.
  - With Clop quit, the original uploads and the `Clop:` log line appears.
  - With Clop not installed, the toggle is disabled and the link shows.
  - No Clop floating result appears and the clipboard is unchanged.

**Built 2026-10-21** on `phase-7-clop`, as specified apart from these differences and additions:
- **Clop version.** The fixtures and the recorded reply are from Clop 3.6.2, which keeps `pHYs`; 3.4.3 (the probe version) dropped it. The `eXIf`-only DPI test stays as the worst case.
- **Order inside `startUpload`.** The key and counter are settled first: a fixed key is used as is, otherwise `{counter}` is drawn when the upload starts, before Clop runs, so counters follow the order uploads start. Then the setting and the running check run on the main actor; with the setting off or no Clop running the job is enqueued at once (the log line for "not running" is written there). Only when Clop will run does a `Task` wait for it.
- **Delete during optimisation cancels the upload.** `optimisingIDs` maps each waiting record to the token of its attempt. `cancelUpload` removes the record, marks it failed with "Upload cancelled." and refreshes the overlay: nothing is enqueued and no key was reserved. A retry started before the first Clop call returns gets a new token, so the first task finds its token gone and drops its bytes. A record deleted from history meanwhile is not enqueued either.
- **Changing upload settings during optimisation is safe.** The coordinator counts, per lane (queue identity), the uploads still waiting for Clop (`clopWaitsPerLane`); a lane the Upload tab replaced is not dropped from `drainingQueues` before those jobs reach it, on every path including the cancelled one.
- **Settings tab.** `clopInstalled` starts false and `load()` sets it when the tab appears, so LaunchServices is asked once per appearance and not on every view rebuild.
- **Release entitlements.** The Release build carries exactly the `mach-lookup.global-name` exception for the two port names plus the four earlier entitlements (`app-sandbox`, `network.client`, `files.user-selected.read-write`, `files.bookmarks.app-scope`), and no `get-task-allow`.
- **Tests.** 839 tests in 98 suites pass. The manual checklist is `docs/testing/phase-7-clop-manual-checklist.md`; it has not been run.

**Placement.** About a day. It sits with the Phase 7 extras.

### 2.8 Phase 5 design: scrolling capture (2026-10-21)

**Scope and order.** Phase 5 captures content taller than the screen by stitching frames of one area as it scrolls vertically. It ships two scrolling modes on one engine, in this order: **manual** (the user scrolls, TidyShot captures as they go) and **auto-scroll** (TidyShot posts scroll-wheel events and stops at the end by itself). Manual mode comes first because it needs no permission beyond Screen Recording and works in every app that redraws when it scrolls; auto-scroll is an opt-in layer that hands over to manual mode whenever it fails. This reverses the order in the Phase 5 bullets of section 6 and in the 2.4 sketch ("Horizontal scrolling and a manual 'scroll yourself' mode come after vertical works"); both were amended on delivery. Horizontal scrolling is deferred (see Deferred). Research, probes and sources: `research.md` next to this draft.

**Feasibility under the App Sandbox (settled 2026-10-21).** A sandboxed app may post synthetic events. The sandbox profile (`/System/Library/Sandbox/Profiles/application.sb`) has no rule against it and allows the WindowServer connection that `CGEvent.post(tap:)` uses; no entitlement is needed, so `project.yml` keeps its four entitlements. The gate is the TCC PostEvent privilege, checked by `CGPreflightPostEventAccess()` and requested by `CGRequestPostEventAccess()`, which System Settings lists under Privacy & Security > Accessibility. Apple DTS (forum thread 820594, 2026) states that PostEvent "is compatible with the App Sandbox", while the general Accessibility APIs (AXUIElement) are not; TidyShot uses none of the latter. A probe app signed with TidyShot's entitlements ran sandboxed, reported `CGPreflightPostEventAccess() == false`, and its posted scroll events were dropped silently (0 of 3 delivered, against 1 of 1 for an in-process control). Whether a posted event reaches another app after a real grant was still unchecked on this Mac when Phase 5 was built (no one had granted PostEvent to the build); the hand check is the first item of the permission section of the Phase 5 checklist, with the probe run of `probes/README-probes.txt` as its fallback. Two fragilities are known and designed around: an ad-hoc-signed rebuild loses the grant, as it loses Screen Recording; and a posted wheel event goes to the window under the pointer, so auto-scroll runs only while the pointer is over the area. App Review guideline 2.4.5 has rejected sandboxed apps that post events; that matters only for a Mac App Store build, and TidyShot ships Developer ID (section 4).

**Starting a capture.** A fourth capture command, **Capture Scrolling**, joins the menu after Capture Fullscreen (`Capture Scrolling  ⌃⇧5`, built by `captureItem` like the others) and the Shortcuts tab (`Capture scrolling:`). `KeyboardShortcuts.Name.captureScrolling` has the initial shortcut ⌃⇧5. It opens the selection overlay in a new `SelectionMode.scrolling`: the crosshair, loupe and snapshot of area mode, plus the window hover highlight of window mode. A drag selects an area; a click without a drag picks the highlighted window's frame, clipped to its display. Either way the result is `.area(rect:display:)`, captured from the display, so the stitched image of a window keeps whatever lies behind its rounded corners (window captures with transparent corners stay single-shot). An area shorter than `ScrollCaptureLimits.minimumAreaHeightPoints` (100) is refused with `notifyError("Select an area at least 100 points tall.", title: "Scrolling capture")`. The mouseUp choice moves into a pure `SelectionOutcome.resolve(mode:dragRect:hasHighlight:) -> SelectionOutcome` (`.area(CGRect)`, `.window`, `.cancel`) so the three modes are tested; `SelectionController.updateHover` and the `WindowPicker` run in `.window` and `.scrolling`, the snapshot task in `.area` and `.scrolling`.

**The session.** After selection the overlay is dismissed and two windows appear:
- *Area frame* (`ScrollAreaFrameWindow`): a borderless, transparent window at `.floating` level whose content draws a 2 pt dashed outline (the adaptive two-tone stroke from 2.6, white line over a black halo) just outside the area, `ignoresMouseEvents = true`, collection behaviour `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`. It never takes clicks or scrolls, so wheel events reach the app beneath.
- *Control panel* (`ScrollCapturePanel: NSPanel`, `.nonactivatingPanel`, `.floating`, `canBecomeKey == true` so Return and Escape work while TidyShot is active), 240 pt wide, hosting the SwiftUI `ScrollCaptureView` like the Quick Access panel. `ScrollPanelGeometry.frame(panelSize:area:visibleFrame:)` places it 12 pt right of the area, else 12 pt left (both top-aligned with the area), else inside the area's bottom-right corner 12 pt from its edges, always clamped to the visible frame of the area's screen. Its height follows the preview, between 220 and `min(560, area height)` pt; an area shorter than 220 pt still gets a 220 pt panel, since the controls need that much.

The panel shows, top to bottom: the live preview (the stitched image so far, scaled to the panel's width and anchored to its bottom, so the newest rows show); the size readout in image pixels with monospaced digits, `2,560 × 7,340 px`; a status line; the **Scroll automatically** checkbox (before Start only); and the buttons. Before Start the buttons are **Cancel** (`.cancelAction`) and **Start** (`.defaultAction`); while capturing, **Cancel** and **Done** (`.defaultAction`). Pressing the Capture Scrolling shortcut again acts as Start, then as Done. **Escape cancels from anywhere**: a second name, `KeyboardShortcuts.Name.cancelScrollingCapture` (initial Escape, no modifiers, no recorder row), is registered at launch, disabled at once, enabled when a session opens and disabled when it closes, so Escape works while the user's app is frontmost and is never swallowed outside a session. A Carbon hotkey needs no Input Monitoring; KeyboardShortcuts refuses modifier-less keys only in its recorder.

The stream starts at Start, not at selection, so the first frame is the page as the user arranged it. `isCapturing` stays true for the whole session (it runs inside `withCaptureLock`), so the other capture commands and their menu items are disabled meanwhile.

**Exact strings.** `ScrollCaptureStatus` (pure, tested) maps the session state to the status line:
- ready, manual: `Click Start, then scroll down slowly.`
- ready, auto: `Click Start, then hold the pointer over the area.`
- manual, capturing: `Scroll down slowly. Click Done at the end.`
- manual, lost its place: `Too fast. Scroll back up a little.`
- auto, scrolling: `Scrolling… Move the pointer away to pause.`
- auto, waiting for the pointer or paused: `Paused. Move the pointer over the area to continue.`
- auto, handed over to manual: `Auto-scroll lost its place. Scroll back up a little, or click Done.`
- auto, end reached: `Reached the end.`
- either, height cap: `Reached the 65,536 pixel limit.`
- finishing: `Stitching…`

Without the PostEvent grant the checkbox is off and disabled and an **Allow Auto-Scroll…** link button sits under it, opening the permission window. Failure notifications use `notifyError(_:title:)`: a stream error with rows already stitched saves them and posts `The capture stopped early: <reason> TidyShot saved what it had.` titled `Scrolling capture stopped`; with nothing stitched it posts `<reason>` titled `Scrolling capture failed`.

**Auto-scroll permission.** `PostEventPermission` (Capture/PostEventPermission.swift) mirrors `ScreenCapturePermission`: `isGranted` (`CGPreflightPostEventAccess()`), `request()` (`CGRequestPostEventAccess()`), and `openSystemSettings()` with `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. `AutoScrollPermissionWindowController` shows `AutoScrollPermissionView`, built like the Phase 0 `PermissionView` and polling the grant once a second:
- title `Accessibility access for auto-scroll` (`systemImage: "scroll"`);
- body `To scroll other apps for you during a scrolling capture, TidyShot posts scroll-wheel events. macOS lists this under Privacy & Security > Accessibility. TidyShot posts them only while a scrolling capture runs. Without it, you scroll and TidyShot captures as you go.`;
- buttons **Request Access** (default) and **Open System Settings**; once granted, they are replaced by `Access granted. Auto-scroll is ready.` in green. The window's own title bar reads `TidyShot`, as the Phase 0 permission window's does;
- caption `If auto-scroll stays unavailable after you allow it, quit and reopen TidyShot.`

The menu shows no item for this permission: it is optional, and the panel is where it matters. The checkbox value persists as `AppSettings.scrollingAutoScroll` (default true), effective only while the grant holds.

**Frame source.** `ScrollFrameSource` (nonisolated final class, `SCStreamOutput` and `SCStreamDelegate`) runs one `SCStream` per session:
- filter `SCContentFilter(display:excludingApplications: [own] exceptingWindows: [])`, where `own` is the `SCRunningApplication` with `processID == getpid()` from a shareable-content fetch made after the panel and frame are on screen. That excludes the panel, the frame, the Quick Access overlay and any editor without the window-number race; when TidyShot is not listed, it falls back to the `overlayWindows()` window-number match, generalised into `OverlayWindowLookup.windows(numbers:engine:)` and shared with `SelectionController`.
- configuration: `sourceRect` = `Geometry.displayLocal(rect, in: display.frame)`, `width` and `height` from `Geometry.pixelSize(points:scale:)` with `CaptureEngine.scale(forDisplayID:)`, `minimumFrameInterval` 1/30 s, `queueDepth` 4, `pixelFormat` `kCVPixelFormatType_32BGRA`, `showsCursor = false`, and `colorSpaceName` set to the display's own colour space (`CGDisplayCopyColorSpace(displayID)`), so the stitched pixels match a one-shot area capture of the same display.
- Each `.complete` sample is copied out of its `CVPixelBuffer` on the sample-handler queue into a `ScrollFrame` (tightly packed BGRA `Data` plus a grey plane, luminance `(77R + 150G + 29B) >> 8`) and the buffer is released at once, so the stream's pool never starves. `.idle` samples become `.idle(time)`. Events reach the session through an `AsyncStream<FrameEvent>` (`.frame(ScrollFrame)`, `.idle(ContinuousClock.Instant)`) with `bufferingNewest(1)` for frames, so a busy stitcher always gets the newest frame and drops the rest. When an idle would push a frame the consumer has not read yet out of the buffer, the source puts the frame back and drops the idle, so the last frame before the page goes still is never lost. Frames carry no time: the session stamps each with its clock when it reads it.
- The source is not restartable. `stop()` finishes the events after any frame still buffered, so Done awaits the read loop and takes that frame before it finishes. A stream that stops by itself (`didStopWithError`) does the same: it records the error in `stopError` (a `Mutex`, written on ScreenCaptureKit's queue) and finishes the events, sending no event of its own, which would push an unread frame out of the one-deep buffer. When the session's events end while it is still capturing (Done and Cancel leave `.capturing` before they stop the source), the stream stopped by itself, and the session asks the source for `stopError`. A stream that stops without an error gives the reason `The screen recording stream stopped.` (`ScrollCaptureSession.streamStoppedReason`). A `stop()` that runs while `start()` is still suspended (the filter fetch or `startCapture`) wins: `start()` returns without a capture, or stops the capture it had just begun, so Escape or Cancel pressed while the stream starts never leaves a capture running; the session also stops the source again when `start()` returns after the session ended.
- The macOS screen-recording indicator shows while the stream runs; that is the price of a 30 fps source, and it goes away at Done or Cancel.

`protocol FrameSource { func start() async throws -> AsyncStream<FrameEvent>; func stop() async; var stopError: (any Error)? { get } }` lets tests drive the session with synthetic frames.

**Overlap finder.** `OverlapFinder` (Scrolling/OverlapFinder.swift, pure, nonisolated, Sendable) compares the last accepted frame A with a new frame B, both grey, and returns `OverlapMatch`: `.still`, `.moved(dy: Int, top: Int, bandEnd: Int, score: Double)` or `.lost`. `dy` is how far the content moved up, so B's row y shows A's row y + dy. The steps, with the values the probe passed with:
1. *Scrollbar strip.* The rightmost `scrollbarStripPoints` (16) times scale columns are never hashed: overlay scrollbars appear and move while scrolling.
2. *Still.* Rows are hashed (FNV-1a, 64 bit) over all other columns. A row is informative when its hash occurs at most `maxRepeat` (4) times in A, which drops blank rows, rules and repeated list items. The leading and the trailing run of rows equal at the same y (a sticky header and footer, which are equal whatever happened) are left out (a row counts as equal when at most `stillTolerance` (2) of its `stripes` stripes differ and none of the differing stripe cells shows content the other frame has at another row, so an animated element does not break the runs but a scroll of a narrow column does); if at least `stillFraction` (0.9) of the informative rows between the two runs are equal at the same y, or none remains, the result is `.still`. Counting the chrome would read a small scroll of a sparse page under tall fixed chrome as still. A spinner, caret or GIF therefore does not count as movement.
3. *Moving columns.* Columns identical at the same position in every row of A and B are dropped (fixed sidebars, empty margins). None left gives `.still`.
4. *Header and footer.* Leading rows equal at the same y are the sticky header (`top`), trailing equal rows the footer (`bandEnd` is the first footer row), each capped at `maxStaticFraction` (0.4) of the height. A band shorter than 16 rows gives `.lost` (or `.still`, by the rule of step 8).
5. *Stripes.* Each row of the band is hashed in `stripes` (8) vertical stripes of the moving columns, so an animated element spoils one stripe of the rows it covers instead of whole rows. Without stripes, the probe's 40x40 spinner made every match `.lost`.
6. *Vote.* Every informative stripe cell of B votes for each `dy = yA - yB` (nonzero) at which A has the same stripe hash. Candidates are ranked by votes, then by closeness to `predicted` (auto mode passes the posted step, manual mode the previous dy), then by smaller |dy|, then forward (positive) over backward, which settles repeated content.
7. *Verify.* The best five candidates are scored over every informative cell of the overlap; the first with `score >= acceptScore` (0.8) and at least `minInformativeRows` (8) times stripes / 2 cells wins. Otherwise `.lost`, except as step 8 says.
8. *Change in place.* When no candidate is accepted but the leading or the trailing run of equal rows of step 2 is longer than `maxStaticFraction` of the height, longer than any header or footer can be, and the rows between are no more than `maxStaticFraction` of the height, part of the band stayed put: nothing scrolled, and the rows between changed in place (Terminal output in a window not yet full, a new chat message that does not scroll the list). The result is `.still`, not `.lost`, so manual mode does not show the too-fast line and the stitcher commits nothing, and auto mode counts it as a still. A jump past the band changes the whole band and stays `.lost`.

Cost: 31 ms for a 2560x1800 pair that moved and 15 ms for an unchanged one on one M5 Max core, so a Retina area stitches at about 30 frames a second on a background core.

**Stitcher.** `ScrollStitcher` (pure, nonisolated) keeps BGRA output rows in one `Data` reserved for the cap (pages are committed only as rows are written). Output row equals content row of the first frame. It holds the last accepted frame and its content offset:
- `add(_ frame:) -> StitchStep` runs the finder against the last accepted frame. `.moved` with `dy > 0` commits rows of the previous frame from `max(committedHeight - offset, 0)` (the first commit starts at row 0, so the first frame's header is kept once; there is no header-height precondition) up to `bandEnd`, then makes the new frame the last accepted, with `offset += dy`. `dy <= 0` (the user scrolled back up), `.still` and `.lost` commit nothing, and matching stays against the last accepted frame, so scrolling back into overlap recovers. The probe's 900 px jump recovered this way.
- `finish() -> StitchedImage` commits the last frame from where the output stops to its bottom, footer included, and returns width, height and the BGRA `Data`.
- Commits never pass `maxPixelHeight`; `isFull` reports the cap.
- Committing from the previous frame, in content coordinates, keeps the output contiguous when one pair over-reads a header or footer (blank rows equal at the same y), and the footer appears only once, at the end.
- `previewRows(maxWidth:)` gives a box-downscaled copy of rows committed since the last call, at most 360 px wide, which the session appends to the live preview at most 4 times a second.

`ScrollStitchEngine` (actor) owns the stitcher off the main actor: `begin(first:)`, `add(_:) -> StitchProgress { heightPixels, step, previewDelta }`, `finish(scale:colorSpace:) -> ScaledImage?`. `finish` wraps the stitched `Data` in a `CGDataProvider` without copying and builds the CGImage (`bitsPerComponent` 8, `bytesPerRow` width x 4, `byteOrder32Little | noneSkipFirst`, the display colour space), returning `ScaledImage(image:scale:)` with the display's scale. The PNG then carries DPI 72 x scale through `ImageEncoder.pngData(from:scale:)`, as every capture does.

**Settling and the end (pure, tested).**
- `FrameSettler` takes `.frame(hash, at:)` and `.idle(at:)` and reports settled when no frame with a new row hash arrived for `quiet` (150 ms), or after `timeout` (1.5 s) from the step, whichever comes first. Content is compared, not just the status, because a complete frame arrives for a change elsewhere on the display.
- `ScrollEndDetector` takes each auto-mode step's `OverlapMatch` and returns `.continue`, `.retryAfter(Duration)`, `.reverseDirection`, `.shrinkStep`, `.handOver` or `.end(EndReason)`. The first `.still` after a step waits 700 ms and retries (lazy loading); a second `.still` ends with `.reachedEnd`. `.moved` resets both counts. When the first step of a session moves backwards, it reverses the direction once (natural scrolling may invert synthetic deltas); a backward move later counts as a loss, so a page that scrolls the wrong way hands over instead of looping. When the first step of a session shows `.still` (at the top of a page in an app that inverts synthetic deltas, the step pushes against the top), the driver tries the other direction once, as a fresh first step, before the end detector counts any still. Both are the driver's decisions, tested in `AutoScrollDriverTests` (`shrinksThenHandsOverAfterThreeLosses`, `triesTheOtherDirectionWhenTheFirstStepIsStill`, `aPageThatNeverMovesEndsAfterTryingBothDirections`). A `.lost` halves the next step down to 40 pt, after the driver first scrolls back by what the step that lost the place posted, so the smaller step starts from overlap with the last accepted frame; three in a row hand over to manual. The height cap ends with `.heightLimit`. Manual mode has no end detector: the user clicks Done, and the cap ends it too.
- `AutoScrollPlan.events(forPoints:)` splits a step into wheel events of at most 50 pt, posted 10 ms apart; the first step is half the area's height and each later one is 0.6 of the last band height in points.

**Auto-scroll driver.** `ScrollEventPoster` (protocol, the real one nonisolated) posts `CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .pixel, wheelCount: 1, wheel1: -points, wheel2: 0, wheel3: 0)` with `scrollWheelEventIsContinuous` set to 1, at `.cghidEventTap`. `AutoScrollDriver` (MainActor) loops while the session runs: if `NSEvent.mouseLocation` (polled 20 times a second, no permission needed) is outside the area, it pauses and shows the paused line; otherwise it checks the grant, posts one step, waits for `FrameSettler`, feeds the settled frame to the engine with the points posted as `predicted`, and applies `ScrollEndDetector`'s decision. The pointer is checked first, so the grant (a TCC preflight) is never asked while paused. A step is a burst of up to about 80 ms, so before each of its wheel events after the first the driver checks the pointer and the grant again; when the pointer has left the area (or moved onto the panel, which can sit inside the area and which `ScrollCaptureController`'s environment reports as outside) or the grant has gone, the rest of the step is not posted, and the part that went out settles and is integrated as any step (the finder measures `dy`). The driver checks the pointer and the settler every 50 ms (the 20 a second above); `FrameSettler` compares a hash of every third grey row, leaving out the scrollbar strip, against the frame before the step. TidyShot never moves the pointer: auto-scroll starts when the pointer enters the area after Start (and after the first frame), and the user takes over by moving it out. If the grant is revoked mid-session (`isGranted` checked before every wheel event, never while paused), the driver hands over to manual. `.end` finishes the session as Done does, after the end line has shown for 0.4 s; the driver hands that to the session (`finishSoon(showing:)`, a task of the session's own, as the manual cap's) and returns, because Done cancels the driver's task.

**Session model.** `ScrollCaptureSession` (MainActor, `@Observable`) holds `phase` (`.ready`, `.capturing(ScrollMode)`, `.finishing`, `.ended`), `heightPixels`, `status: ScrollCaptureStatus`, the preview `CGImage` and `autoScroll`. It is built with a `FrameSource`, a `ScrollEventPoster` and a clock, so its tests run on synthetic frames. Manual mode feeds every frame event to the engine and turns `.lost` into the too-fast line until the next `.moved`; a change in place is `.still` (Overlap finder, step 8) and leaves the line as it was. `ScrollCaptureController` (MainActor) shows the frame and panel, runs the session and resolves `run(rect:display:) async -> ScrollCaptureOutcome` (`.image(ScaledImage)`, `.cancelled`, `.failed(String, partial: ScaledImage?)`) through a continuation, like `SelectionController.select`. Done with no movement saves the first frame alone, an ordinary area capture. Done is ignored until the first frame has arrived, and the size readout shows the area's own height until then. The preview is the first frame at full size until rows are stitched, then the stitched rows at most 360 px wide. The session stamps each frame it reads with its clock (`latestFrameAt`) and bumps `frameSerial`; the driver settles on those, and in auto mode it, not the read loop, feeds settled frames to the engine (`integrate`). A cancel during the stream start ends the session at once, and the source is stopped again when its `start()` returns, so no capture outlives the session.

**One save path.** `AppCoordinator.captureScrolling()` runs inside `withCaptureLock`: `loadContent()`, then `selector.select(mode: .scrolling, content:)`, `selector.dismiss()`, then `scrollCapture.run(rect:display:)`. An `.image` (or a `.failed` with a partial image) becomes `CaptureResult(image:scale:target: .area(rect:display:))` and goes to `save(_:)` unchanged: the after-capture action, the file or pending file, the history record, the thumbnail, the Quick Access overlay with Annotate, and the upload all behave as for any capture (`CaptureResult.target` is read nowhere downstream). Two changes in `save(_:)` keep a tall capture from blocking the main actor: the PNG encode, and the TIFF for the clipboard when `copyImageNow` holds, run in `Task.detached(priority: .userInitiated)`, and the clipboard write uses `Pasteboard.copy(pngData:tiffData:)`. Every capture takes that path; for a normal capture the cost is one hop. An image over 16,384 px on a side goes on the clipboard as PNG only, here and on every other clipboard write of an image (Height cap and tall images).

**Preview before save or upload.** The live preview in the panel is the preview section 6 asks for: nothing is written, recorded or uploaded until Done, and Cancel or Escape discards everything. After Done the normal Quick Access overlay follows, with Annotate and Delete, so a bad result is fixed or removed in two clicks. A separate review window between Done and save is not built (Decisions).

**Height cap and tall images.** `ScrollCaptureLimits.maxPixelHeight` is 65,536 px (32,768 pt at 2x), raised from 16,384 on 2026-10-21 after a long Reddit thread stopped at the old cap (decision 2). At the cap and 3094 px wide the output is 811 MB of pixels, plus two frame copies. Each consumer of an image that tall, as measured on the M5 Max:
- *Stitcher.* The output reserves width x 4 x cap bytes up front; an allocation that large is virtual until written, so the footprint grows with the rows (reserving 811 MB adds nothing). `finish()` and the engine wrap the rows in a CGImage without a copy (`Data` bridges to the same bytes).
- *Live preview.* `PreviewRows` keeps only the newest `ScrollCaptureLimits.previewMaxRows` (2,048) rows of the downscaled preview: the panel shows under 800 of them, and a preview as tall as a narrow capture would exceed a texture.
- *Save.* The PNG encode runs off the main actor and adds about 25 MB; 3 s for a 3094 x 65,536 page of text.
- *Clipboard.* The TIFF is uncompressed (580 MB at the cap) and making it peaks at 1.2 GB over the image, so an image over `Pasteboard.tiffMaxSide` (16,384 px) on a side goes on the clipboard as PNG only (`Pasteboard.companionTIFF`); every current Mac app reads PNG. The TIFF-only fallback after a failed PNG encode is made at any size, since it is the only copy.
- *Thumbnail and overlay.* Top crops of the in-memory image, which share its pixels.
- *Hover preview and the file-based thumbnail.* A cut image is decoded subsampled (`ThumbnailMaker.subsampleFactor(for:maxSide:)`, 1, 2, 4 or 8, as much as keeps the top at least as large as the result): drawing the cut top inflates the whole PNG, at 217 MB instead of 792 MB for the 1,200 px preview, in about 0.5 s.
- *Upload.* One signed PUT of the PNG in memory, as for any capture; S3's single PUT takes up to 5 GB.
- *Editor.* Metal accepts 2D textures up to 32,768 px on the M5 Max (`MTLTextureDescriptor` validation rejects 32,769) and 16,384 on Apple GPUs before family 9 and on Intel Macs, so `BaseImageView` shows an image over `ImageTiling.maxTileSide` (16,384 px) on a side as stacked layers (2.6, Rendering): a 65,536 px capture is four 16,384 px strips with the same filters and frames, so zoom, pan and Fit work as before. The highlighter backdrop draws the strips that meet its clip. Core Image reads only the region around each effect, so the redaction tiles render near either end of a 65,536 px base (tested at 40,000 px). `EditorFlattener` copies the base in the same strips, because drawing a CGImage into a bitmap converts it through a buffer as large as what is drawn: whole, the base would briefly need another 811 MB; in strips the peak is the flattened bitmap plus one strip (about 1.7 GB with the base, down from 2.3 GB).

For the 96x72 overlay well and the 320 px thumbnail, `ThumbnailMaker.thumbnail(from:maxSide:)` gains a top crop: an image taller than 3 times its width is cut to its top `width * 3 / 2` rows before scaling, so the thumbnail shows the start of the page instead of a sliver (`ThumbnailMaker.cropForThumbnail(_:)`, pure, tested). The ImageIO path (`thumbnail(from source:maxSide:)`, for a record whose thumbnail is not written yet and for the Recent Captures hover preview) crops the same way: it reads the pixel size with `CGImageSourceCopyPropertiesAtIndex` and, when the crop would cut, decodes the image (subsampled, above), cuts it to the top and draws that. The record's `pixelWidth` and `pixelHeight` are the full size.

**Architecture.** New code lives in `TidyShot/Scrolling/`, picked up by XcodeGen's recursive source path:
- pure, nonisolated, Sendable: `ScrollFrame.swift` (frame, grey conversion), `OverlapFinder.swift`, `ScrollStitcher.swift`, `FrameSettler.swift`, `ScrollEndDetector.swift`, `AutoScrollPlan.swift`, `ScrollCaptureLimits.swift`, `ScrollCaptureStatus.swift`, `ScrollPanelGeometry.swift`;
- `ScrollStitchEngine.swift` (actor), `ScrollFrameSource.swift` (SCStream, nonisolated), `ScrollEventPoster.swift`, `ScrollClock.swift` (the clock protocol the session and driver sleep on, with the system clock);
- MainActor: `ScrollCaptureSession.swift`, `AutoScrollDriver.swift`, `ScrollCaptureController.swift`, `ScrollCapturePanel.swift`, `ScrollCaptureView.swift` (SwiftUI), `ScrollAreaFrameWindow.swift`.

Elsewhere: `Capture/PostEventPermission.swift` and `Capture/AutoScrollPermissionWindowController.swift`; `Selection/SelectionOutcome.swift` and `Selection/OverlayWindowLookup.swift`; edits to `Selection.swift` (the `.scrolling` case), `SelectionController.swift`, `SelectionView.swift`, `Shortcuts.swift`, `StatusMenuController.swift`, `ShortcutsSettingsView.swift`, `AppSettings.swift` (`scrollingAutoScroll`), `ThumbnailMaker.swift` and `AppCoordinator.swift` (`captureScrolling()`, the detached encode, registering both new names). The concurrency rule of 2.6 applies: the frame copy runs on the stream's sample-handler queue, the finder and stitcher inside the engine actor, and any nonisolated async helper that must leave the main actor is `@concurrent`.

**Tests (Swift Testing).** A shared `SyntheticPage` helper in TidyShotTests renders pages and frames as the probe did (sticky header and footer, fixed sidebar, moving scrollbar thumb, animated square, text whose pixel rows differ, blank gaps, repeated list items, noisy image blocks).
- `OverlapFinderTests`: exact dy for steps of 1, 3, 40, 462 and band - 16 px; `.still` for identical frames and for frames differing only in the animated square; header and footer heights; a fixed sidebar ignored; scrollbar thumb movement ignored; repeated content resolved by `predicted`; `.lost` for a step larger than the band; negative dy for a scroll back up; an all-blank pair is `.still`; a change in place near the top or the bottom is `.still` and one in the middle `.lost` (`aChangeInPlaceIsStillNotLost`).
- `ScrollStitcherTests`: the probe's five scenarios (auto 60% steps, manual irregular with a scroll back, too fast then recover, plain, tiny steps) reproduce header + page + footer exactly outside the animated square; output stops at `maxPixelHeight` exactly with `isFull`; a single frame finishes as itself; the footer appears once.
- `FrameSettlerTests`, `ScrollEndDetectorTests` (two stills end, the lazy-load retry, reset on movement, reverse once, shrink and hand over, the cap), `AutoScrollPlanTests`, `ScrollPanelGeometryTests` (right, left, inside, clamped), `ScrollCaptureStatusTests` (every string above), `SelectionOutcomeTests` (three modes).
- `ScrollStitchEngineTests`: synthetic BGRA frames through the actor, then `ImageEncoder.pngData`, then `ImageEncoder.decode`: decoded scale is 2, the size and every pixel match the expected page.
- `ScrollCaptureSessionTests` with a fake `FrameSource`, poster and clock: Start, frames, Done gives an image; Cancel gives nothing; the cap finishes by itself; `.lost` shows the too-fast line and clears on the next movement, and a change in place does not show it; a stream that stops by itself keeps the frame buffered before the stop; the checkbox takes effect only with the grant. `ScrollFrameSourceTests` checks that a stop by itself records the reason and still delivers the buffered frame. Auto mode's pointer gating, end and hand-over are tested in `AutoScrollDriverTests`.
- `AutoScrollDriverTests` (a fake world of a scrolling page, a fake poster and clock): the end on two stills, lazy loading, pointer gating (and no grant check while paused), the reverse and the other-direction tries, shrink then hand over, the grant going, a burst cut short when the pointer leaves or the grant goes after its second event, the cap; the session-level auto tests live here, and `ScrollCaptureSessionTests.autoScrollNeedsTheGrantAndTheCheckbox` covers the checkbox and the grant.
- `ThumbnailMakerTests` for the top crop, on the CGImage path and on a tall PNG through ImageIO; `AppSettingsTests` for the new key.

The selection overlay, the panel, the stream and real event posting are covered by `docs/testing/phase-5-manual-checklist.md`: Safari, Chrome, Slack (a long channel), Notes, Finder list view, Terminal and Xcode; a site with a sticky header and a cookie footer; dark mode; natural scrolling on and off; two displays at mixed scales; Escape with another app frontmost; a too-fast flick and recovery; the 65,536 px cap; the permission flow, including re-granting after an ad-hoc rebuild; Upload-only mode end to end; Annotate on a capture at the cap; and a one-shot area capture of the same region compared pixel for pixel with the stitched image's first screen.

**Risks.**
- *Auto-scroll delivery (hand check open at delivery, 2026-10-21).* The driver, the poster and the permission flow are built and tested against fakes; whether a wheel event posted at the HID tap reaches Safari, Terminal and a chat window after the grant has not been observed yet. If it fails, the fallback view exists (`ScrollCaptureSession.isAutoScrollAvailable`, false without an environment: the checkbox stays visible, off and disabled, with the caption `Auto-scroll is unavailable: macOS did not deliver TidyShot's scroll events.` in place of the Allow Auto-Scroll… link, and manual mode is unaffected), and turning it on is a one-line change in `ScrollCaptureController` (pass `nil` as the session's `autoScrollEnvironment`). Replace this bullet with the observed result after the checklist's permission section is run.
- *Grant loss on rebuild.* Ad-hoc signing (Config/Local.xcconfig on Tim's Mac) loses the PostEvent grant on every build, often leaving a stale switch on in System Settings; remove the entry and add it again, or sign with Apple Development.
- *Content the finder cannot place.* A blank stretch taller than the area, a page of identical rows, or animation across the whole width leaves no informative overlap. Manual mode shows the too-fast line until overlap returns; auto mode reads the blank stretch as still and ends there. A jump past the band in an area of which more than 60 % at the top and bottom together does not change, with more than 40 % at one edge, (a static pane, or a blank stretch at the same rows in both frames) reads as a change in place, `.still`: manual mode then shows no too-fast line, and auto mode counts a still instead of a loss.
- *Fixed overlays inside the band* (a floating chat button, a sidebar scrolling at a different speed) are stitched in each time they appear. The checklist records what Safari and Chrome do with them.
- *Lazy loading and infinite scroll.* The 700 ms retry covers most loads; an infinite feed runs to the cap.
- *Wrong pane.* Wheel events go to the view under the pointer; with several panes in the area, the user points at the one to scroll.
- *Memory and time at the cap.* 811 MB of pixels at 3094 px wide, about 3 s and more to encode (off the main actor), four 203 MB textures in the editor, and about 1.7 GB while the editor flattens it for Save. A Mac with 8 GB will page.
- *Colour.* If `colorSpaceName` from `CGDisplayCopyColorSpace` is refused, the stream falls back to sRGB, and the checklist comparison with a one-shot capture shows the difference.

**Deferred.** Horizontal scrolling (the finder transposes cleanly, but the panel, the end detector and the event poster need a direction, and wide content is rare); scrolling up to capture content above the start; a window-only filter with transparent corners; a self-timer before Start; a review window between Done and save; raising the cap above 65,536 px.

**Decisions (defaults chosen 2026-10-21, confirmed in the plan PR).**

1. **Manual mode first, auto-scroll second in the same phase.** Recommended. The sandbox allows auto-scroll, but delivery has not been observed here yet and an ad-hoc rebuild drops the grant, so manual mode is the part that always works. Alternative: auto first, as section 6 has it.
2. **Height cap 65,536 px** (32,768 pt at 2x). Revised 2026-10-21 from 16,384 px, which kept the editor's single texture within every Apple GPU's limit but stopped a long Reddit thread at 3094 x 16,384. The editor now tiles a tall image into 16,384 px layers, and the clipboard drops the TIFF above 16,384 px. Alternative: no cap, which leaves an endless feed to run until memory gives out.
3. **No review window after Done.** Recommended: the live preview is the preview, Done commits, and the overlay's Annotate and Delete handle the rest. Alternative: a window with Save, Annotate and Discard before anything is written or uploaded, which matters most in your upload-only mode, where Done uploads at once.
4. **Window pick captures the window's frame from the display**, corners included. Recommended: one capture path, and scroll events must reach the window on screen anyway. Alternative: a desktop-independent window filter with transparent corners, which also captures through overlapping windows that the scroll events cannot pass.
5. **Shortcut ⌃⇧5** for Capture Scrolling, and Escape as a session-only global hotkey. Recommended; ⌃⇧5 is free and sits next to the other three.
6. **Exclude all of TidyShot from the stream** by application rather than by window number. Recommended: no lookup race, and nothing of TidyShot belongs in a scrolling capture. Alternative: the window-number match the area capture uses.
7. **Thumbnail top crop** for images taller than 3:1. Recommended, so the overlay and Recent Captures show the top of the page. Alternative: keep the aspect-fit sliver.
8. **Optional: sign with Apple Development** (`Config/Local.xcconfig`) for Phase 5 testing, so Screen Recording and the auto-scroll grant survive rebuilds. Recommended; ad-hoc works but needs both permissions re-granted after every build.

**Phase 5 (built).** Delivered 2026-10-21 on `phase-5-scrolling`; the full suite reads `Test run with 581 tests in 72 suites passed` after the whole-branch review fixes; the manual checklist is `docs/testing/phase-5-manual-checklist.md`. The build follows the text above; where it differs or decided something 2.8 left open:
- The finder treats a narrow scrolling column as movement. A differing stripe cell does not count against stillness when its content appears at another row of the other frame (within `maxRepeat` occurrences), so the lines of a Terminal inside a wide selection, or a chat list beside a static area, are never read as `.still`; a spinner whose pixels appear at no other row still is animation. The ranking's last tie-break prefers a forward shift over a backward one. A pair with no changed whole row returns `.still` before any stripe hashing.
- The stitcher commits from `committedHeight - offset` of the previous frame, so a pair that over-reads a header or footer cannot open a gap or repeat rows, and the first commit starts at row 0 (no precondition on the header height).
- A known risk that the checklist records and the build does not solve: a chat's bouncing typing dots may read as a small scroll of a narrow column.
- The panel is top-aligned with the area when it sits beside it and is at least 220 pt tall for any area; the permission window's buttons give way to the granted line; the driver's pointer and settling poll is 50 ms; a backward move after the first step counts as a loss.
- Stopping during the stream start never leaves a capture running (see Frame source).
- Whole-branch review fixes (2026-10-21): each wheel event of an auto-scroll step checks the pointer and the grant, and the grant is not asked while paused (Auto-scroll driver); a stream that stops by itself records its reason instead of sending an event that could drop a buffered frame (Frame source); a change in place is `.still`, not `.lost` (Overlap finder, step 8); the driver ends through the session's own finish task; the ImageIO thumbnail path crops tall images (Height cap and tall images).
- Cap raised to 65,536 px (2026-10-21, decision 2): the editor tiles a tall image (`ImageTiling`, `BaseImageView`, the highlighter backdrop, `EditorFlattener`), the clipboard drops the TIFF above 16,384 px, the live preview keeps its newest 2,048 rows, and the hover preview decodes a tall PNG subsampled; see Height cap and tall images. The suite then reads `Test run with 600 tests in 75 suites passed`.
- Not done in code, by decision: no entitlement and no `project.yml` change (the diff of both against `main` is empty); the delivery fallback of the Risks list is built but not switched on (see the first Risk).
- - Review fixes (after the whole-branch review): `BackgroundLayout` also has `maximumCanvasArea` (16,384 x 16,384 pixels), and `make` returns nil above it as it does above the side limits; a 1:1 canvas for a 16,000 px tall 2x scrolling capture would otherwise have been about 1 GB, and the editor's caption for a nil layout is unchanged. With the area limit the side limit can only be reached by padding that the area limit also refuses; it stays as the check that runs first. `WallpaperSource.wallpapers(only:)` takes an optional display and captures only that display's wallpaper window; `BackgroundFillSource.desktopPicture` uses it, so a window capture with a desktop-picture fill no longer captures every display inside the capture lock. The desktop covers still call `wallpapers()` for all displays. The filter sits inside the ScreenCaptureKit call and is not pure, so it has no unit test. The editor clears its cached desktop picture and renders the fill again on `windowDidChangeScreen` and on `NSWorkspace`'s `activeSpaceDidChangeNotification`, only while a desktop-picture background shows; the observer is removed in `windowWillClose`. `CustomBackgroundStore.preview(maxSide:)` uses `ThumbnailMaker.scaled`, so the swatch shows the whole of a tall image, not its top. When `compose` or `fill` has no image for a desktop-picture or custom-image fill, it logs `Background: no image for <fill>, drawing the first gradient` once per call before drawing preset 0.
- Colour space: the composed output is always sRGB, while an export without a background keeps the capture's colour space. A Display P3 capture is therefore converted to sRGB once a background is on.

Observations from the checklist run are still to be written down here by Tim: what Safari and Chrome do with the fixed spinner, footer and overlay scrollbar; the time at the 65,536 px cap and from Done to the overlay; natural scrolling, from halfway and from the top; the stitched-versus-one-shot comparison and the profile and DPI; how the editor behaves at 65,536 px; what a chat's typing dots do; and whether PostEvent delivery works (see the first Risk). None of the GUI checks had been run when this was written.

### 2.9 Phase 6 design: overlay and capture polish (2026-10-21)

**Scope and order.** Phase 6 finishes the P1 rows of the triage table in 2.1 that Phases 2 to 5 left minimal: the full Quick Access overlay (stacking, close and restore, multi-display, Save As…, drag-out, Pin), Capture Previous Area, All-in-One, Freeze screen, Self-Timer, the cursor and window-shadow options, Pin to screen, and the `tidyshot://` URL scheme. It ships as two PRs, 6a on the branch `phase-6-polish` and 6b on `phase-6b-polish`: **6a** is what Tim touches on every capture (he runs upload-only mode, the overlay at the top right, and hotkeys): the overlay, Capture Previous Area, Freeze screen and the cursor and shadow options; **6b** adds the new ways to start a capture: All-in-One, Self-Timer, Pin and the URL scheme, which comes last so every command it names exists. Section 6 estimated 2 to 3 days; the work below is closer to 3 days for 6a and 4 for 6b, mostly in the All-in-One overlay and the stacked panel. Nothing in Phase 6 adds an entitlement or a Swift package. Sources and the probes to run: `docs/superpowers/research/phase-6-research.md`.

**What exists today.** `QuickAccessController` shows one `QuickAccessPanel` (340 x 104, `.floating`, non-activating, movable by its background) on the screen under the pointer, replacing the previous one; `QuickAccessView` has the thumbnail (click reveals a save-folder file), the status column (Copy URL, Retry), and Annotate, Close and Delete. There is no drag-out, no Save As…, no restore, and what section 3 said about dragging the card out to drag the local file was never built. Captures do not exclude the panel: a fullscreen capture taken while a card shows contains it, and so does an area capture over it. `CaptureEngine` captures windows with `SCContentFilter(desktopIndependentWindow:)` and `ignoreShadows = true`, so window shots already have transparent rounded corners and no shadow, and `EditorFlattener`, `ThumbnailMaker` and the clipboard TIFF all keep alpha; what remains of "window shot with transparent background" is the shadow option and the cursor (below). `SelectionController` already takes one snapshot per display for the loupe, after the overlay windows are up and with the overlay excluded by window number; the capture itself is taken live after mouse-up, while the overlay is still on screen. With Show cursor on, that live capture contains TidyShot's own crosshair at the mouse-up point for area and window captures, which is a bug this phase fixes.

#### 6a: the overlay, Capture Previous Area, Freeze screen, cursor and shadow

**Stacking.** `QuickAccessController` holds an ordered list of cards, newest first, one `QuickAccessPanel` and `QuickAccessModel` each, all on one screen. A new capture's card appears at the configured corner and the older ones slide away from it by one card height plus 10 pt (down from a top corner, up from a bottom corner), moved together through `NSAnimationContext` and `animator().setFrame(_:display:)` (0.2 s), which does not block the main actor. The stack holds at most `settings.overlayMaxCards` cards (Overlay tab, `Show up to N overlays`, `Show up to 1 overlay` at 1, 1 to 8, default 5), further limited to what fits the screen's `visibleFrame`; a card pushed past the limit closes as `.pushedOut` and can be restored. Each card runs its own auto-close countdown. When it runs out with the pointer over the card, it starts again; where the pointer is at that moment decides, not the last hover event, so a card that slid away from a still pointer closes, and the card that slid under it waits. A card never closes under a running drag-out. A close slides the cards behind it into the gap only once the pointer has left the stack (polled every 250 ms); a new capture and a display change lay the stack out at once. Lowering the setting takes effect at the next layout, a capture, a close or a display change, which closes the oldest surplus cards as `.pushedOut`. A card is no longer movable by dragging its background (`isMovableByWindowBackground = false`): dragging a card is drag-out, and the stack positions its cards. `QuickAccessStackLayout` (Overlay/QuickAccessStackLayout.swift, pure, nonisolated) owns the geometry: `frames(count:cardSize:corner:visibleFrame:margin:spacing:) -> [CGRect]` (index 0 is the newest, at the corner, with `OverlayGeometry.frame` for that one) and `capacity(cardHeight:visibleHeight:margin:spacing:limit:) -> Int`. With 1 card and Show up to 1, behaviour equals Phase 5's.

**Which display.** A new Overlay setting, `Show on` (`settings.overlayDisplay`, `OverlayDisplayChoice`): `Display of the capture` (default, `.capture`), `Display with the pointer` (`.pointer`, Phase 5's rule) and `Main display` (`.main`, `NSScreen.screens[0]`). The display of the capture comes from `CaptureResult.target`: the area's or fullscreen display, or the display under a window's centre (`CaptureEngine.displayID(containing:)`); a scrolling capture uses its area's display. `OverlayScreenChoice.index(choice:captureDisplayID:pointerIndex:screenDisplayIDs:) -> Int` (pure) falls back to the pointer's screen, then to screen 0. The whole stack lives on one screen: a capture shown on another display moves the existing cards there with it, so cards never split across displays. `NSApplication.didChangeScreenParametersNotification` re-lays the stack out on the screen it was on, or on screen 0 when that screen is gone.

**Card layout.** `QuickAccessView.size` stays 340 x 104. Close moves out of the right column into a hover-only badge at the card's top-left corner (`xmark.circle.fill` on a material circle, help `Close`), as the macOS screenshot thumbnail and CleanShot place it. The right column becomes Annotate (`pencil.tip.crop.circle`, help `Annotate`), Pin (`pin`, help `Pin to screen`, 6b; in 6a the column has Annotate and Delete) and Delete (unchanged help strings). The status column's button row gains **Save As…** in every state: `Copy URL  Save As…` once uploaded, `Retry  Save As…` after a failure, `Save As…` while uploading and after a plain save. A failed upload's message is the card's tooltip. A right-click or Control-click on the card opens a context menu (SwiftUI `.contextMenu`) with every action: `Copy URL` (disabled without a link), `Copy Image`, `Save As…`, `Annotate`, `Pin to Screen` (6b), `Reveal in Finder` (only with a save-folder file), a separator, `Close`, `Delete…`. A click on the thumbnail still reveals a save-folder file; a drag from anywhere on the card except a button is drag-out.

**Close and restore.** Every close reports a reason: `QuickAccessCloseReason` = `.user` (badge or menu), `.autoClose`, `.pushedOut`, `.draggedOut`, `.deleted`, `.editorOpened`. The first four push the record id onto `ClosedOverlays` (Overlay/ClosedOverlays.swift, pure): a most-recent-first list of at most 10 ids without duplicates. **Restore Closed Overlay** pops the newest id that still has a history record and is not already shown, and shows its card again at the corner with the record's current state and its stored thumbnail (`ThumbnailProvider`), with the normal auto-close. It is a menu item after Recent Captures (`Restore Closed Overlay`, enabled when `ClosedOverlays` holds a restorable id) and a shortcut, `KeyboardShortcuts.Name.restoreOverlay` (Shortcuts tab, `Restore closed overlay:`, no default). Repeated use walks back through the list, also at a full stack: the card that the restore pushes out goes to the back of the list (`ClosedOverlays.didCloseBehind`), not the front, so the next restore reaches an older card instead of the one just pushed out. The list lives in memory and empties at quit; Recent Captures remains the long-term way back. `.deleted` and `.editorOpened` closes are not restorable (the record is gone, or the editor now holds the capture); neither is a capture whose delete is under way, and opening the editor on a capture whose card is already closed takes it off the list. The menu item is not disabled while a capture runs. The retained image (`latestCapture`) still belongs to the newest capture only and is dropped when its card closes, so a restored card's Annotate loads from the file or the bucket as Recent Captures does.

**Save As….** `AppCoordinator.saveAs(recordID:)` (shared by the card's button, its context menu, and the pin's context menu in 6b) runs after menu tracking, activates the app and opens an `NSSavePanel` (not a sheet; the overlay is non-activating) with PNG as the only type and the name and folder from `EditorNaming.saveAsSuggestion(for:saveFolder:namer:currentCounter:)`, so the suggestion matches the editor's: the record's own file name in the save folder, otherwise the file name template's name drawn without a counter. The bytes come from `imageData(of:)` (the local file, or the drag copy below, or a signed GET for an upload-only capture whose file is gone, with `Downloading <key>` posted under the title `Saving a copy…` while it runs). The PNG is written as is, with no re-encode, through the URL the panel returns (the panel's grant covers the write under the sandbox), and `Saved` with the file name is posted when notifications are on. Save As… exports a copy: the record, its link and `lastCaptureURL` do not change.

**Drag-out.** Dragging a card puts one file on the drag pasteboard, as an `NSURL` file URL, with the card's thumbnail as the drag image and `.copy` as the only operation outside the app. The file is always a copy in TidyShot's container, started at mouse-down on the card by `DragFileStore` (Output/DragFileStore.swift, nonisolated, Sendable), in a detached task; the drag session begins once the file exists (a drag that passes the 3 pt threshold earlier waits for the next mouse-dragged event) in `<container tmp>/Drag/<record id>/<name>.png`:
- **From a file.** A save-folder file is cloned with `FileManager.copyItem` (an APFS clone, instant on the same volume) inside the save folder's security scope; a pending file in `pending/` is cloned directly.
- **Kept after upload.** In upload-only mode the pending file is deleted when the upload succeeds. While a card shows that record, `.uploaded` now moves the file into the drag folder (`DragFileStore.adopt(id:name:moving:)`, a rename) instead of deleting it; the record changes exactly as before (`fileURL = nil`, `fileIsTemporary = false`), so history, Delete and retention are unaffected. This keeps drag-out working in Tim's mode after the URL is on the clipboard.
- **From the bucket.** A restored card whose record has no local file starts a quiet prefetch (signed GET, no notification) into the drag folder when it appears; until that finishes, dragging the card does nothing.

The name is `DragFileName.name(for:suggestion:)` (pure): the last path component of the key behind the record's link (`uploadedKey`, or `priorUpload.key` while the editor uploads over a link; `aSIS7.png`, so the file matches the link that is on the clipboard), with `:` turned into `-`, a leading `.` into `_` and `.png` added when missing, otherwise (no key, or a key ending in `/`) the Save As suggestion's file name. A restored card's file keeps that name whichever copy supplies it (`DragFileStore.restage`). An edit saved over the capture's file removes its drag copy (it holds the pixels from before the edit, and `imageData(of:)` would read it first); the next press on a showing card stages the edit again. A card's drag folder is removed 60 s after the card closes (a receiver such as Slack may still be reading it after the drop), at once when the record is deleted, and the whole `Drag` folder is swept at launch. With `Close after dragging out` on (Overlay tab, `settings.overlayCloseAfterDrag`, default true), a drag that ends with an operation other than none closes the card as `.draggedOut`.

**Why a file URL and not a file promise (amends decision 6).** Decision 6 named `NSFilePromiseProvider` for drag-out, on the assumption that a sandboxed app cannot hand out a file. It can: a file in the app's own container is readable by the app, and dropping a file onto another app grants that app access to it, including from a protected location (`docs/superpowers/research/phase-6-research.md`, CVE-2026-28910 write-up: "dropping a file onto an app grants that app access to it"). A promise defers writing until the drop and lets the receiver pick the folder, which matters only when no file exists; here a file always exists by drag start. Promises are also the less certain flavour: Finder, Mail and Photos accept them, but whether Chromium-based receivers (Slack, Chrome, every Electron app), where Tim drags screenshots, accept them could not be confirmed (`docs/superpowers/research/phase-6-research.md`), while every receiver that takes a dropped file reads a file URL. The Phase 6a checklist drags to Finder, Slack, Chrome, Safari (a Gmail compose window), Mail, Messages and Notes; if one of them refuses the file URL, the fallback is an `NSFilePromiseProvider` subclass that also writes `public.file-url` (Apple's file-promise sample pattern) for the same container file, which needs no other change. The fallback is written in the Phase 6a plan (Task 6, Step 9) and is not built; it is built only if Tim's checklist run shows a receiver refusing the file URL.

**Exclude the overlay from captures.** Cards are TidyShot UI and stay out of every capture, as CleanShot's overlay does. `QuickAccessController.windowNumbers` lists the cards on screen; the area capture's exclusion list becomes the selection windows plus the cards (one `OverlayWindowLookup.windows(numbers:engine:)` call, which `SelectionController.overlayWindows()` already makes), and `captureFullscreen()` excludes the cards too, with a lookup only when a card is showing. Pins (6b) and editor windows stay in captures: they are content the user placed on screen. Scrolling capture already excludes all of TidyShot.

**Capture Previous Area.** Every area capture stores its rect, CoreGraphics global points, as `settings.lastAreaRect` (a `StoredRect` Codable value under the key `lastAreaRect`): Capture Area, the All-in-One area, Self-Timer areas, Capture Scrolling's area and a URL command's area (a `capture-scrolling` rect only once its stitched image is saved, so a cancelled URL session leaves the stored rect as it was). **Capture Previous Area** (menu `Capture Previous Area  ⌃⇧6`, Shortcuts tab `Capture previous area:`, `KeyboardShortcuts.Name.capturePreviousArea`, initial ⌃⇧6) captures that rect again with no selection overlay: `PreviousArea.resolve(rect:displays:) -> PreviousArea.Resolution` (pure; `.area(CGRect, displayID)` clipped to the display under the rect's centre, `.offScreen` when the centre is on no display or the clipped rect has less than 1 pt on a side, `.none` when no rect is stored or it is smaller than 1 pt) picks the display, and the capture runs live through `capture(_:excludingWindows:)` with the cards excluded, then `save(_:)`; it does not write `lastAreaRect`, so a clipped rect never shrinks the memory, and a Capture Scrolling area is stored only when it is at least 100 pt tall. Without a stored rect it posts `Capture an area first.` titled `No previous area`; with the rect on no connected display, `The previous area is not on a connected display.` with the same title. Freeze does not apply (there is no selection). The same stored rect is what All-in-One preselects (6b), so one memory serves both, as CleanShot's "remembers the last selection" does.

**Freeze screen.** A Capture setting, `Freeze screen while selecting` (`settings.freezeScreen`, default false), caption `Area selections show a still image of the screen and the capture is cut from it, so menus, tooltips and video stay as they were when you pressed the shortcut.` With it on, `SelectionController.select(mode:content:freeze:)` captures every display before any overlay window appears (one `engine.capture(.display(_:))` per display, one after the other, the cards excluded, `showsCursor` from the setting; a task group of main-actor children is rejected by the Swift 6 compiler, because `SCDisplay` and `SCWindow` are not Sendable), then shows the overlay with each view's `snapshot` already set and `isFrozen = true`, so the view draws the snapshot opaque under the dimming and the screen appears to stop. After mouse-up the coordinator asks `selector.frozenCapture(for: displayID)` and crops instead of capturing again: `FreezeCrop.pixelRect(selection:displayFrame:scale:imageSize:) -> CGRect?` (pure; origin and size rounded as `Geometry.pixelSize` rounds, so a frozen crop and a live capture of the same rect have the same pixel size; a rect that sticks out by at most one pixel is moved inside, keeping its size; nil when it leaves the image by more), then `FreezeCrop.cropped`, which cuts with `CGImage.cropping(to:)` and draws the cut into a context of the crop's own size, so the result owns just its pixels and the display snapshot (about 60 MB for a 5K display) is freed after `dismiss()` instead of living as long as the card, then `save(_:)` with `.area(rect:display:)`. A display whose snapshot failed falls back to a live capture. Freeze applies to area mode and to All-in-One's Capture. Window mode, scrolling and Self-Timer ignore it: a window is captured from its own surface, which a frozen backdrop cannot match, scrolling is live by nature, and a timer captures later by definition. The overlay appears after the snapshots instead of before them; at two displays that is one ScreenCaptureKit round trip each, run one after the other (measured in the checklist). With freeze off, nothing changes: the loupe snapshot is still taken after the overlay is up.

**Cursor.** `Show cursor in screenshots` stays in the Capture tab with a caption: `Fullscreen, previous-area, self-timer and URL captures show the pointer where it is. Area captures show it only with Freeze screen on. TidyShot never captures its own crosshair.` The rule, applied in `AppCoordinator`: a capture taken while the selection overlay is up (live area and window captures) passes `showsCursor = false`; a frozen snapshot, a fullscreen, previous-area, Self-Timer or URL-rect capture passes the setting. `CaptureOptions` gains `init(settings:duringSelection:)` so the rule is in one place and tested (`CaptureOptionsTests`).

**Window shadow.** A Capture setting, `Include window shadow` (`settings.windowShadow`, default false, which keeps today's output), caption `Window captures keep transparent rounded corners either way.` `CaptureOptions` gains `windowShadow`, and `CaptureEngine` sets `config.ignoreShadows = !options.windowShadow` for `.window`. A shadow lies outside `window.frame`, so with it on the output size cannot come from the frame: the engine sizes it from the filter, `filter.contentRect.size` times `filter.pointPixelScale` (both on `SCContentFilter` since macOS 14). Whether `contentRect` grows by the shadow, and whether `SCScreenshotManager` draws the shadow at 1:1 into that size, is not documented. Phase 6a builds the system shadow, sized by `CaptureEngine.windowPixelSize` (a degenerate filter falls back to the frame), and commits the probe `probes/window-shadow/probe.swift`, which captures a Finder and a Slack window both ways and records `contentRect`, the output size and the alpha at the corners; running it is Tim's checklist item, with the result in `docs/superpowers/research/phase-6-research.md`. If the system shadow does not come out at 1:1, the synthetic one written in the plan (Task 1's fallback) is built: `WindowShadow.composite(_:scale:)` (pure) captures without the shadow, pads the image by 40 pt on each side and draws a black shadow under it with blur radius 20 pt, offset 0 by 10 pt downward and opacity 0.4. Either way the result keeps alpha outside the shadow.

#### 6b: All-in-One, Self-Timer, Pin, URL scheme

**All-in-One.** One shortcut opens a selection that stays adjustable and offers every capture kind from a toolbar, as CleanShot's All-in-One does. Menu `All-in-One  ⌃⇧1` (first capture item), Shortcuts tab `All-in-One:`, `KeyboardShortcuts.Name.allInOne`, initial ⌃⇧1. It runs `selector.selectAllInOne(content:freeze:preselect:)` (`SelectionMode.allInOne`):
- **Start.** With a rect to start from, the overlay opens with it already selected and adjustable: a URL command's rect (`preselect`), otherwise `settings.lastAreaRect` when it is on a connected display (`SelectionAdjust.restored`: on the display holding the rect's centre, clipped to it, at least 4 pt a side). A preselect never writes `lastAreaRect`. An `all-in-one` URL command's start rect (its own or `lastAreaRect`) opens **disarmed** (`SelectionView.keyCaptureArmed` false, through `selectAllInOne(…armed: false)`): the overlay takes the key from the app the user is typing in, so Return, keypad Enter and a double-click inside the rect do not capture until the user presses anywhere in the overlay or uses the toolbar's size fields, lock or a button; a double-click counts only when the overlay was armed before its press, so the second click of a double-click begun elsewhere arms without capturing. Arrows and Escape work disarmed; a new rect (drag or window click) is armed; a toolbar button pressed disarmed only arms (Cancel still cancels), since the sender's rect places the toolbar. `capture-window`, `self-timer` and `capture-scrolling` without a rect open their overlays disarmed too (`select(…armed: false)`): the first press only arms, picking no window and starting no drag. The hotkey and the menu open armed. Without one the overlay opens like Capture Scrolling's selection: crosshair, loupe, and the window under the pointer highlighted.
- **Selecting.** A drag draws a new rect; a click without a drag takes the highlighted window's frame, clipped to its display, as the rect and remembers the window. Once a rect exists it shows eight handles: dragging a handle resizes, dragging inside moves, dragging outside starts a new rect, and a click outside it without a drag takes the window under the pointer when there is one and otherwise keeps the rect. A new rect on another display clears the first (the selection lives on one display). A handle is within 6 pt of its edge (on a narrow rect the nearer side wins). A moving edge stops 4 pt short of the opposite one, so the rect never flips, and the pointer is rounded to a whole point first, so the edges that are not dragged stay exactly where they were, also on a half-point drag; every result is whole points. Arrow keys move the rect by 1 pt, Shift-arrow by 10 pt; Return and keypad Enter capture; Command and Control combinations are not the overlay's. All geometry is clamped to the rect's display. The Window button stays enabled through a resize, move, nudge or typed size of a window's rect and is dropped by a new drag or a preselect.
- **Toolbar.** `AllInOneToolbar` (AppKit, a subview of the selection window, so the area capture excludes it with the overlay) sits centred 8 pt under the rect, or 8 pt above it when there is no room, or inside its bottom edge when neither fits, kept 8 pt inside the screen's sides and below the menu bar's safe area (`AllInOneToolbarPlacement.frame(toolbarSize:selection:screenBounds:)`, pure), and it hides while a drag, resize or move runs. Left to right: `W` and `H` fields (points, whole numbers above 0; Return applies the value, the rect grows from its top-left corner and is clamped and moved inside the display, and the field then shows the size the rect really has; Escape drops what was typed and shows the real size again; either gives the keyboard back to the selection, so a second Escape cancels), an aspect-ratio lock button (`lock` / `lock.open`, help `Lock aspect ratio`), a separator, then **Capture** (`camera`, help `Capture area (Return)`), **Window** (`macwindow`, enabled when the rect came from a window click, help `Capture the window with transparent corners`), **Fullscreen** (`display`, help `Capture this display`), **Scrolling** (`scroll`, help `Scrolling capture of this area`), **Timer** (`timer`, help `Capture this area after <n> seconds`), and **Cancel** (`xmark`, help `Cancel (Escape)`). Return or a double-click inside the rect is Capture; Escape cancels.
- **Aspect lock.** With the lock on, a handle drag keeps the ratio of the rect at the moment the lock was turned on, or of a new rect set while locked: a corner takes the larger of the pointer's width and its height times the ratio, an edge sets its side and grows the other about the rect's centre, and both stop at the display. Typing W changes H (and the other way; W wins when both are given). The lock state is one value for every display's overlay, so it follows the selection to another display, and persists as `settings.allInOneAspectLock` (default false).
- **Outcome.** `Selection` gains no case; `SelectionController` returns `AllInOneChoice` (`.area(rect, display)`, `.window(SCWindow)`, `.fullscreen(display)`, `.scrolling(rect, display)`, `.timer(rect, display)`) through a separate `selectAllInOne(content:freeze:preselect:) async -> AllInOneChoice?`. The coordinator's `captureAllInOne(intent:preselect:)` maps each to the existing path: an area through the freeze crop or a live capture, and a window through `capture(.window(_:))`, both taken with the overlay up and excluded (`duringSelection: true`, so the pointer is never in them); fullscreen dismisses the overlay first and then captures that display as `captureFullscreen()` does (the overlay's windows and the cards excluded, the pointer from Show cursor, never the crosshair); scrolling hands the rect to `scrollCapture.run(rect:display:)` (refusing a rect under 100 pt with the Phase 5 message); the timer to the Self-Timer countdown below. Every area kind stores `lastAreaRect`.

The resize, move, nudge, clamp and lock arithmetic is pure, in `SelectionAdjust` (Selection/SelectionAdjust.swift): `handle(at:rect:tolerance:) -> SelectionHandle?` (eight handles plus `.inside`), `resized(_:handle:to:lockedRatio:bounds:minSide:) -> CGRect`, `moved(_:by:bounds:) -> CGRect`, `nudged(_:key:shift:bounds:) -> CGRect`, `sized(_:width:height:lockedRatio:bounds:) -> CGRect` and `restored(_:displayFrames:) -> CGRect?`, all in the view's bottom-left coordinates, minimum side 4 pt, results in whole points; `keyCommand(keyCode:hasRect:)` routes Escape, Return and keypad Enter and the arrows, so the key routing is tested here and not through KeyRouting.

**Self-Timer.** Menu `Self-Timer` (after Capture Previous Area), Shortcuts tab `Self-timer:`, `KeyboardShortcuts.Name.selfTimer`, no default shortcut. It opens the selection in a new `SelectionMode.selfTimer`: area mode's crosshair and loupe plus window mode's highlight; a drag selects an area, a click picks the window (`SelectionOutcome.resolve` gains the mode: `.selfTimer` behaves like `.scrolling`, and the controller returns `.window` for a click, as window mode does). The overlay is dismissed, TidyShot gives up activation (`NSApplication.shared.deactivate()`) so the user's app keeps its menus and keys during the countdown, and `SelfTimerController` shows a countdown: a borderless, click-through panel at `.screenSaver` level (set after `isFloatingPanel`, which resets the level), centred on the area (or the window) and kept inside its screen, a 96 pt rounded square with the seconds left in a 48 pt monospaced-digit font and the caption `Esc to cancel`, plus a 2 pt dashed frame around the area. It counts `settings.selfTimerSeconds` (Capture tab, `Self-timer` picker: `3 seconds`, `5 seconds`, `10 seconds`; default 5) down once a second. At zero both panels are ordered out, the controller waits 100 ms for the window server to drop them, and the capture runs live (`showsCursor` from the setting, the cards excluded), then `save(_:)`. The shareable content is read again and the display or window is found in it by id, so a window that moved during the countdown is captured where it is now; a window that is gone posts `The window is no longer on screen.` and a display that is gone `The display is no longer connected.`, both titled `Self-timer`, and nothing is captured. An area writes `lastAreaRect`; a picked window does not. A stored `selfTimerSeconds` other than 3, 5 or 10 reads as 5. Escape cancels through the global Escape hotkey that Phase 5 added for scrolling: `.cancelScrollingCapture` is renamed in code to `.cancelCapture` with the same stored name `cancelScrollingCapture` (nothing to migrate), and the timer enables it while it runs, as the scrolling session does; its one handler cancels whichever of the countdown and the scrolling session runs. The capture lock is held for the whole countdown, so other shortcuts are ignored meanwhile. The countdown ticks are tested through a clock protocol (the `ScrollClock` of Phase 5) in `SelfTimerTests`.

**Pin to screen.** A pin is a floating copy of a capture that stays above other windows. `PinController` (Pin/PinController.swift) owns the pins; each is a `PinPanel` (NSPanel, borderless, `.nonactivatingPanel`, `.resizable`, level `.floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `hasShadow = true`, `canBecomeKey = true`, so it takes keys without activating TidyShot; the level is set after `isFloatingPanel`, which resets it) hosting `PinView`, a layer-backed NSView whose layer shows the image with `.trilinear` minification and a 1 px hairline border.
- **Opening.** From the card's Pin button and context menu, and from a URL command's `action=pin`. The image is the retained capture for the newest card, otherwise the record's PNG through `imageData(of:)` and a detached decode, shared with `openEditor` as `loadImage(for:) async -> ScaledImage?`. An image over 8,192 px on a side is shown from a downsample to the screen's pixel size (`ThumbnailMaker.scaled(_:maxSide:)`, new in 6b; `thumbnail(from:maxSide:)` cuts a tall image to its top and would pin a scrolling capture as a sliver), so a 65,536 px scrolling capture pins as a fitted strip, and the pin keeps the capture's point size for Actual Size. Opening a pin does not close the card and does not take the keyboard. A second Pin on a capture that is already pinned brings its pin forward instead of opening another. Failures are titled `Could not pin the capture` (the download is posted as `Pinning the capture…`, a failed downsample as `The capture is too large to pin.`). The status menu's pin items are not disabled during a capture.
- **Placement.** `PinGeometry.initialFrame(imagePoints:preferred:visibleFrame:) -> CGRect` (pure): the image at its point size, over the spot it was captured from when that is known (an area capture's rect: `latestCaptureArea`, the newest capture's area, set in `save(_:intent:)` right after the record exists), otherwise centred on the pointer's screen; scaled down to fit 80 % of the screen's visible frame; always on screen.
- **Interaction.** Drag anywhere to move. Drag an edge to resize, aspect ratio fixed (`contentAspectRatio`), minimum side 40 pt (a strip already under 40 pt keeps its short side as the floor). A click makes the pin key (`PinView.mouseDown` calls `makeKey()`; dragging a non-activating panel alone does not), so the arrows and Command keys work from the first click. While the pin is key: arrows move it 1 pt and Shift-arrows 10 pt (`PinGeometry.nudged`), Command-plus and Command-minus zoom by 10 % around the centre and Command-0 returns to actual size, both in whole points and within the pin's screen's visible frame (`zoomed(_:factor:visibleFrame:)`, `actualSize(_:imagePoints:visibleFrame:)`), so a capture larger than the screen comes back fitted to it, Command-C copies the image, Escape or Command-W closes. Option-scroll changes opacity in steps of 5 %, between 10 % and 100 %.
- **Context menu.** `Copy Image`, `Save As…`, `Annotate`, `Opacity` (submenu: `100%`, `90%`, `75%`, `50%`, `25%`, with a check on the current one), `Actual Size`, `Lock`, a separator, `Close`.
- **Lock mode.** `Lock` makes the pin click-through (`ignoresMouseEvents = true`), so the app under it gets the clicks, and its border disappears. A locked pin cannot be clicked, so the status menu shows `Unlock Pinned Screenshots` while any pin is locked and `Close Pinned Screenshots` while any pin exists, both before Settings….
- **Lifetime.** Pins live in memory: they close at quit and are not restored at launch. Deleting a capture closes its pins. Pins are TidyShot windows the user put on screen, so captures include them; the scrolling stream excludes them with the rest of TidyShot.

**URL scheme.** `tidyshot://` lets Raycast, Keyboard Maestro, Shortcuts and scripts drive the app. The names follow CleanShot's (`cleanshot://capture-area?action=upload`, `docs/superpowers/research/phase-6-research.md`), so an existing CleanShot macro works after the scheme is changed.
- **Registration.** `project.yml` gains, under the TidyShot target's `info.properties`, `CFBundleURLTypes: [{CFBundleURLName: io.tky.tidyshot, CFBundleURLSchemes: [tidyshot]}]`; `xcodegen generate` writes it into `TidyShot/Info.plist`. Receiving URL events needs no entitlement under the App Sandbox. `AppDelegate.applicationWillFinishLaunching` installs `NSAppleEventManager.shared().setEventHandler(_:andSelector:forEventClass: kInternetEventClass, andEventID: kAEGetURL)`, which keeps SwiftUI's scene machinery from handling the URL and gives the sender (`keySenderPIDAttr`, then `NSRunningApplication(processIdentifier:)?.localizedName`) for logs and notifications. A URL that arrives before `AppCoordinator.start()` finishes (a cold launch from the URL) is queued (at most 8 URLs wait; later ones are dropped with a log line) and run after it; of the queued capture commands only the first that passes the gate runs, and later ones are dropped as during a capture, so a burst before launch cannot open overlays one after another.
- **Commands.** `capture-area`, `capture-window`, `capture-fullscreen`, `capture-previous-area`, `all-in-one`, `self-timer`, `capture-scrolling` (also accepted as CleanShot's `scrolling-capture`), and `restore-recently-closed`. The command is the URL's host (`tidyshot://capture-area`) or its first path component (`tidyshot:capture-area`, `tidyshot:///capture-area`).
- **Parameters.** `action` on every capture command: `upload`, `save`, `copy`, `annotate`, `pin`. `x`, `y`, `width`, `height` and `display` on `capture-area`, `all-in-one` and `capture-scrolling`: points, origin at the bottom-left of the display as in CleanShot, `display` 1-based with 1 the main display (`NSScreen.screens[0]`) and the others in `NSScreen.screens` order, defaulting to the display under the pointer. The four rect values come together or not at all, as plain decimals (an optional `-`, digits, at most one `.` with digits on both sides) of at most 16 characters and at most 100,000 pt in size; `display` is one or two ASCII digits, 1 to 99, and is used only together with the rect (a malformed one is an error even without a rect). Command names, parameter names and actions match ignoring case, after percent-decoding, and the gate sees the decoded command. A parameter a command takes may appear once. On `capture-area` the rect is captured at once (and written to `lastAreaRect`); on `all-in-one` and `capture-scrolling` it is preselected, and a `capture-scrolling` rect skips the selection, is refused under 100 pt with the Phase 5 message, and is stored as `lastAreaRect` only once the stitched image is saved; an `all-in-one` overlay opened by a URL command waits for a touch before Return or a double-click captures (All-in-One, Start). A preselected scrolling session does not activate TidyShot and shows its panel with `orderFrontRegardless()` without making it key: Start and Done are default actions, so a Return typed in the frontmost app must not start a capture of the sender's rect, and Start needs a click (or the hotkey). A preselected session not started within 60 seconds (`ScrollCaptureSession.readyTimeout`, on the session's clock) cancels itself as Cancel does, nothing saved, so a planted session does not hold the capture lock and the global Escape. Sessions from the menu and the hotkey make the panel key as before and have no timeout. Unknown parameters are ignored; a bad value is an error.
- **Actions.** No `action` means the after-capture action in General. `upload` uploads: as `Upload only` when that is the setting (Tim's case), otherwise as `Upload and copy URL`. `save` is `Save and copy image`. `copy` puts the image on the clipboard and nothing else: no file, no record, no overlay, no upload; the shutter sound plays with Play sound, and `Image copied` is posted when notifications are on, with the image's pixel size as its body. `annotate` and `pin` run the after-capture action, then open the editor (`openEditor(recordID:)`) or a pin for the new record. The override travels as `CaptureIntent` (`Capture/CaptureIntent.swift`: `action: AfterCaptureAction`, `copyOnly: Bool`, `then: .none | .annotate | .pin`, `sender: String?`) through every capture function and into `save(_:intent:)`, which now returns the record (`@discardableResult`). Hotkeys and the menu pass `CaptureIntent.standard`, which reads the after-capture setting when the capture starts.
- **Errors and refusals.** Parse errors and refused commands post a notification titled `TidyShot URL command`: `Unknown command “<name>”.`, `Unknown action “<value>”. Use upload, save, copy, annotate or pin.`, `x, y, width and height must be given together, as numbers, with width and height above 0.`, `There is no display <n>.`, `“<name>” is given more than once.` (a repeated parameter that the command takes, found before any value is checked) and `The area leaves less than a point on display <n>.` (a rect clipped away). Every URL notification carries `From <sender>` as its subtitle when the sender is known, and values quoted in a message lose control and format characters and are cut at 40 characters with `…`. A command that arrives while a capture runs is dropped with a log line, never queued; `capture-scrolling` during a scrolling session does not advance it (only the hotkey does).

**URL security.** A URL scheme makes TidyShot a deputy for its Screen Recording permission: any process on the Mac can run `open tidyshot://…` without a prompt, and a web page can after the user allows the browser's "Open TidyShot?" dialog once (Chrome offers "Always allow"). A command that needs a selection is safe by construction, because nothing is captured until the user drags or clicks, and the result shows in the overlay. Two commands preselect a rect, so that holds only with care: `all-in-one` opens its rect disarmed (a Return or a double-click captures only after the user has touched the overlay), and a preselected `capture-scrolling` session is not key, waits for a click on Start, and cancels itself after 60 seconds unstarted. A command that captures **without a selection** (`capture-fullscreen`, `capture-previous-area`, and `capture-area` with a rect) is not: an app with no Screen Recording grant could request one with `action=copy` and read the image from the clipboard, or with the default action in upload mode read the public URL from the clipboard. Upload adds little to that risk on its own (the clipboard is already the leak), so there is no separate upload switch; the gate is on silent capture. The General tab gains a `URL commands` section:
- `Allow URL commands (tidyshot://)` (`settings.urlCommandsEnabled`, default true). Off, every command is refused with `URL commands are off. Turn them on in Settings > General.`
- `Allow URL commands that capture without a selection` (`settings.urlCommandsAllowSilent`, default false), caption `capture-fullscreen, capture-previous-area, and capture-area or capture-text with x, y, width and height capture at once. Any app on this Mac, and any web page you let open TidyShot, can send them, and an allowed command lets the sending app read the result from the clipboard.` Off, those commands are refused with `<command> from <sender> captures without a selection. Allow it in Settings > General > URL commands.`, naming the sender when it is known.
- `restore-recently-closed` only reopens a card and is allowed whenever URL commands are on.

`URLCommandGate.decision(for:enabled:allowSilent:sender:) -> .run | .refuse(String)` is pure and tested; with URL commands off even a URL that does not parse gets the off message. The Release configuration sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` on the app target: ad-hoc "Sign to Run Locally" otherwise adds `com.apple.security.get-task-allow`, which would let any same-user process attach to TidyShot and borrow its Screen Recording grant without a URL at all. Debug keeps it for tests and the debugger. Commands never take a file path: CleanShot's `pin`, `open-annotate` and `add-quick-access-overlay` with `filepath` would have the sandboxed app read a path it has no grant for, and an open panel per call defeats the purpose (Deferred).

#### Settings summary

- **General:** `URL commands` section (two toggles above).
- **Shortcuts:** `All-in-One:` (⌃⇧1), `Capture previous area:` (⌃⇧6), `Self-timer:` (none), `Restore closed overlay:` (none), after the four existing recorders.
- **Capture:** `Freeze screen while selecting`, `Show cursor in screenshots` (new caption), `Include window shadow`, `Self-timer` picker.
- **Overlay:** `Show on`, `Show up to N overlays` (Stepper 1 to 8, `Show up to 1 overlay` at 1), `Close after dragging out`, after Position and Auto-close; history retention stays here.

New `AppSettings` keys: `overlayDisplay` (`capture`), `overlayMaxCards` (5), `overlayCloseAfterDrag` (true), `freezeScreen` (false), `windowShadow` (false), `selfTimerSeconds` (5), `lastAreaRect` (none, JSON), `allInOneAspectLock` (false), `urlCommandsEnabled` (true), `urlCommandsAllowSilent` (false). Section 5's "Advanced (URL scheme, history retention)" tab is not created: URL commands go to General and retention stays in Overlay.

**Status menu after Phase 6.** `All-in-One  ⌃⇧1`, `Capture Area  ⌃⇧4`, `Capture Window  ⌃⇧2`, `Capture Fullscreen  ⌃⇧3`, `Capture Scrolling  ⌃⇧5`, `Capture Previous Area  ⌃⇧6`, `Self-Timer`; separator; Recent Captures, `Restore Closed Overlay`, Retry Failed Uploads, Reveal Last Capture; separator; `Unlock Pinned Screenshots` and `Close Pinned Screenshots` when they apply; Settings…, Quit TidyShot. Every capture item is disabled while a capture runs, as today.

**One save, upload and delete path.** Nothing in Phase 6 writes, uploads or deletes a capture outside the paths of Phases 3 to 5. Every new capture kind (previous area, frozen crop, All-in-One choices, Self-Timer, URL commands) ends in `save(_:intent:)`, so the after-capture action, the file or pending file, the record, the thumbnail, the card and the upload behave as for any capture. Save As… and drag-out export copies and never change the record. The overlay's and the pin's Delete is `deleteCapture(recordID:)`, which now also removes the record's drag folder and closes its pins; a record pruned by retention (`removeFiles(ofPruned:)`) also closes its pins and drops the retained image and pin placement when they are its. `action=copy` is the one capture that makes no record, by request.

**Architecture.** New files:
- `Overlay/`: `QuickAccessStackLayout.swift`, `ClosedOverlays.swift`, `OverlayScreenChoice.swift`, `DragFileName.swift` (pure); `QuickAccessCardDragSource.swift` (an NSView in the card's background, `NSDraggingSource`, wrapped for SwiftUI by `NSViewRepresentable`); edits to `QuickAccessController`, `QuickAccessModel`, `QuickAccessPanel`, `QuickAccessView`.
- `Output/DragFileStore.swift`.
- `Capture/FreezeCrop.swift`, `Capture/PreviousArea.swift`, `Capture/CaptureIntent.swift` (6b), `Capture/WindowShadow.swift` (only if the probe fails), edits to `CaptureEngine`, `CaptureTarget` (`CaptureOptions`; 6b adds `cgFrame` and `areaRect`).
- `Selection/SelectionAdjust.swift`, `Selection/AllInOneToolbar.swift`, `Selection/AllInOneToolbarPlacement.swift`, `Selection/AllInOneChoice.swift`; edits to `Selection.swift` (`.allInOne`, `.selfTimer`), `SelectionController`, `SelectionView` (frozen drawing, handles), `SelectionOutcome`.
- `SelfTimer/SelfTimerController.swift`, `SelfTimer/SelfTimerPanel.swift`.
- `Pin/PinController.swift`, `Pin/PinPanel.swift`, `Pin/PinView.swift`, `Pin/PinGeometry.swift` (pure).
- `URLScheme/URLCommand.swift`, `URLScheme/URLCommandGeometry.swift`, `URLScheme/URLCommandGate.swift` (pure), `URLScheme/URLCommandHandler.swift` (with the `URLCommandTarget` protocol that `AppCoordinator` conforms to, so the handler is tested against a recorder).
- Edits: `AppCoordinator` (`captureAllInOne`, `capturePreviousArea`, `captureSelfTimer`, `restoreClosedOverlay`, `saveAs`, `pin`, `handleURL`, `CaptureIntent`, exclusion of cards, drag-folder hooks in `.uploaded` and delete), `AppDelegate`, `Shortcuts`, `StatusMenuController`, the four Settings views, `AppSettings`, `project.yml`, `Info.plist`.

The 2.6 concurrency rule holds: the freeze snapshots, the drag copy from a save-folder file and the prefetch run detached or `@concurrent`; the panels, controllers and settings are MainActor.

**Tests (Swift Testing).**
- `QuickAccessStackLayoutTests`: four corners, the newest at the corner, spacing 10, capacity on a short screen, a second display's offset, one card equals `OverlayGeometry.frame`.
- `ClosedOverlaysTests`: newest first, cap 10, no duplicates, skips deleted and shown ids, reasons that are not restorable.
- `OverlayScreenChoiceTests`: each choice, a missing capture display, a missing pointer screen.
- `DragFileNameTests`: key name, save-folder name, template name, nested key `shots/2026/x.png` gives `x.png`.
- `DragFileStoreTests` (a temporary directory): stage clones and names, adopt moves, remove, sweep, a second stage replaces the first.
- `FreezeCropTests`: 1x and 2x, a second display with a negative origin, fractional points round as `Geometry.pixelSize`, a rect off the image gives nil, and the size equals `Geometry.pixelSize` for the same rect.
- `PreviousAreaTests`: none, on screen, clipped, off screen after a display is removed.
- `CaptureOptionsTests`: the cursor rule for each capture kind; shadow passes through.
- `SelectionAdjustTests`: each handle, inside move, clamping at each edge, minimum side, aspect lock on corner and edge handles, W/H entry with and without lock, nudges, restore on and off screen.
- `AllInOneToolbarPlacementTests`: below, above, inside, clamped to the screen's sides.
- `SelectionOutcomeTests`: the `.selfTimer` and `.allInOne` modes.
- `SelfTimerTests` with a fake clock: counts 5 to 1, cancel stops before capture, the capture runs once after the panels are gone.
- `PinGeometryTests`: actual size, fit to 80 %, preferred spot kept and clamped, nudges, zoom about the centre, minimum side.
- `URLCommandTests`: every command by host and by path, the alias, every action, rect parsing (all four, missing one, negative width, non-numeric), `display`, unknown command, case of the host.
- `URLCommandGeometryTests`: bottom-left origin on the main display and on a secondary display above and to the left, clipping, a missing display.
- `URLCommandGateTests`: each command against the two toggles; `restore-recently-closed`.
- `CaptureIntentTests`: `upload` under each after-capture action, `copy`, `annotate`, `pin`, none.
- `URLCommandHandlerTests`: parse, gate, drop while a capture runs, rect placement, the queue before start (8, and only the first capture command runs), the sender in the notification subtitle.
- `AppSettingsTests` for each new key and default; `ShortcutsTests` for the new names and initial shortcuts.

The panels, drag-out to real apps, the frozen overlay, All-in-One handles, the countdown, pins and URL launches are covered by `docs/testing/phase-6a-manual-checklist.md` and `phase-6b-manual-checklist.md`: drag-out to Finder, Slack, Chrome, Safari Gmail, Mail, Messages and Notes in each after-capture mode, before and after the upload finishes, and from a restored card; stacking at all four corners with five captures and a sixth; two displays at mixed scales with each `Show on` choice and with a display unplugged; restore after each close reason; Save As… in upload-only mode after the pending file is gone; a fullscreen capture with three cards showing (none in the image); freeze over a playing video and an open menu, with and without Show cursor, timing the overlay's appearance; the shadow probe's output against a system screenshot; All-in-One from no previous rect and with one, each toolbar button, aspect lock, W/H entry, arrows; a self-timer over an open menu; pins at each opacity, locked and unlocked, across Spaces and over a full-screen app, and a pin of a 65,536 px capture; each URL command from Terminal (`open 'tidyshot://capture-area?action=upload'`), from Raycast and from Keyboard Maestro, the silent gate both ways, a cold launch from a URL, and `lsregister -dump | grep -i tidyshot` to see which build owns the scheme.

**Risks.**
- *Which build owns the scheme.* LaunchServices registers every TidyShot.app it sees: the Debug build in DerivedData, `.build-rel` and any copy in /Applications. `open tidyshot://…` may start a stale one. The checklist removes stale registrations (`lsregister -u <path>`) and runs the Release build from one place.
- *Drag-out receivers.* The file-URL choice rests on the claim that every target reads a dropped container file; one that does not (a sandboxed receiver that rejects the extension) gets the promise fallback described above.
- *Freeze latency.* The overlay waits for one display capture per display. If the checklist measures more than about 150 ms at two displays, the snapshots move to a stream started at the hotkey, or freeze becomes area-only on the pointer's display first.
- *Window shadow.* The system shadow is built; if Tim's probe finds that `SCScreenshotManager` squashes or clips it, the synthetic shadow written in the plan is built as a follow-up.
- *All-in-One in a key window.* The selection windows activate TidyShot (as today) and now hold text fields; Return and Escape must reach the view while a field is not editing. `SelectionAdjust.keyCommand` covers the routing in tests. No selection mode cancels on focus loss, and 6b does not add it: the overlay stays up until Escape, Cancel or a choice.
- *Stack and Spaces.* Cards join all Spaces; a capture taken in a full-screen app shows the stack there. Animated re-layout after a close must not move a hovered card out from under the pointer: it waits while the pointer is over the stack (a new capture lays out at once).
- *Memory.* Pins of large captures hold their decoded image (59 MB for a 5K capture); several 65,536 px pins are capped by the 8,192 px downsample.
- *URL abuse.* With silent capture allowed, any local process can take a screenshot through TidyShot. The default is off and the caption says so; Tim turns it on knowingly for Keyboard Maestro.

**Deferred.** Swipe gestures on cards and "hide overlays temporarily" (CleanShot has both); a card size setting; the macOS screenshot-thumbnail style of a card that follows the pointer; pins restored at launch and Pin on Recent Captures rows; `filepath` commands (`pin`, `open-annotate`, `add-quick-access-overlay`), `open-settings`, `open-history`, desktop-icon commands, and `start` / `autoscroll` on `capture-scrolling`; a per-app allow-list for URL commands; recording commands; a background or padding around window shots (Phase 7, Background tool); a self-timer before a scrolling capture's Start.

**Decisions (defaults chosen 2026-10-21, confirmed in the plan PR).**

1. **Two PRs, 6a then 6b.** Recommended: 6a (overlay stack, close and restore, display choice, Save As…, drag-out, Capture Previous Area, freeze, cursor and shadow) is what you use with every capture; 6b (All-in-One, Self-Timer, Pin, URL scheme) adds new entry points. Alternative: one PR, at the cost of a review of about 14 tasks at once.
2. **Drag-out hands a file URL to a copy in the container, not a file promise.** Recommended; amends decision 6. Slack and Chrome read file URLs reliably, a file always exists by drag start, and the promise subclass stays as the fallback if a receiver refuses.
3. **Keep the upload-only file while its card shows,** moved into the drag folder after the upload, so you can drag the capture after the URL is copied. Recommended. Alternative: drag-out only until the upload finishes, then from a download.
4. **URL commands: one gate on capturing without a selection, default off; no separate upload switch.** Recommended: area, window, All-in-One, Self-Timer and scrolling commands need your drag or click; fullscreen, previous-area and rect captures do not, and the clipboard already leaks their result to any local app. Turn the second toggle on for Keyboard Maestro macros that capture fullscreen. Alternative: a third toggle for `action=upload`.
5. **`action=copy` means clipboard only,** with no file, no record and no overlay. Recommended, as CleanShot's copy. Alternative: a normal capture with the image copied.
6. **Shortcuts:** All-in-One ⌃⇧1, Capture Previous Area ⌃⇧6; Self-Timer and Restore Closed Overlay without defaults. Recommended; both defaults are free and sit beside ⌃⇧2 to ⌃⇧5.
7. **Cursor:** never TidyShot's crosshair; area captures show the pointer only with Freeze screen on, window captures never. Recommended. Alternative: draw the pointer ourselves into live captures, which needs the deprecated `NSCursor.currentSystemCursor`.
8. **Freeze screen off by default,** and ignored by window, scrolling and Self-Timer captures. Recommended until the checklist measures the delay it adds.
9. **Stack of up to 5 cards, newest at the corner, cards no longer draggable to move,** Close as a hover badge at the top-left. Recommended. With your top-right corner, older cards move down.
10. **Overlay on the display of the capture** by default. Recommended; on one display it is the same as today.
11. **Window shadow off by default; the system shadow, with a synthetic one written as the fallback if Tim's probe fails.** Recommended.
12. **Pins appear in captures, live only until quit, and open over the spot they were captured from.** Recommended.
13. **URL rects use CleanShot's convention** (points from the bottom-left of the display, display 1 the main one), so CleanShot macros port by changing the scheme. Recommended. Alternative: top-left origin like the rest of TidyShot's CoreGraphics code.
14. **Self-Timer selects first, then counts down.** Recommended, so the capture is of what you chose. Alternative: count down, then capture the display under the pointer.
15. **Quick Access cards are left out of every capture.** Recommended, as CleanShot does; today a fullscreen capture contains them.

**Phase 6a (built).** Delivered 2026-10-21 on `phase-6-polish`. The suite reads `Test run with 684 tests in 85 suites passed`; the hand checks are in `docs/testing/phase-6a-manual-checklist.md`. The build follows the text above, as amended in place, with these points:
- Window shadow: the system shadow is built (`ignoreShadows = !windowShadow`, the size from `contentRect` times `pointPixelScale` through `CaptureEngine.windowPixelSize`, the frame for a degenerate filter). `probes/window-shadow/probe.swift` is committed and builds; it has not been run.
- Drag-out: the copy starts at mouse-down on the card and the drag session begins once the file exists.
- Save As…: a needed download is posted as `Downloading <key>` under the title `Saving a copy…`.
- The Overlay stepper reads `Show up to 1 overlay` at 1 and `Show up to N overlays` otherwise.
- The cards move together through `NSAnimationContext` and `animator().setFrame(_:display:)`, 0.2 s, not the `animate:` form of `setFrame`, which animates one window after another.
- The file-promise fallback for drag-out is written in the plan and not built.
- Constants as designed: card 340 x 104, spacing 10 pt, corner margin 16 pt, 1 to 8 cards (default 5), 10 closed ids, a 60 s delay before a closed card's drag folder goes, a 3 pt drag threshold. The new `AppSettings` keys and defaults are `overlayDisplay` (`capture`), `overlayMaxCards` (5), `overlayCloseAfterDrag` (true), `freezeScreen` (false), `windowShadow` (false) and `lastAreaRect` (none); `capturePreviousArea` is ⌃⇧6 and `restoreOverlay` has no default. The strings match 2.9.
- Freeze: the snapshots are taken one display after the other, not in a task group; two displays cost two round trips. `FreezeCrop` moves a crop that sticks out by one pixel inside.
- Stack: lowering `Show up to N overlays` takes effect at the next capture, close or display change, not at the stepper. A close slides the cards up only after the pointer has left the stack; a new capture slides them at once. A card's countdown looks at where the pointer is when it runs out, so a card that slid away from a still pointer closes.
- Restore Closed Overlay walks back through the closed list even when the stack is full (the card a restore pushes out goes to the back of the list). A capture being deleted, and a capture opened in the editor from Recent Captures, are not restorable. The menu item stays enabled while a capture runs.
- Drag copies: the name follows the object key (`priorUpload.key` too; `:` becomes `-`, a leading `.` becomes `_`) also after a restore. An edit saved over a capture's file replaces its drag copy, so Copy Image, Save As… and Annotate never read pre-edit pixels, and the next drag stages the edit.
- The failed-upload message is the card's tooltip, not the status text's.
- Capture Previous Area reports a stored area that leaves less than 1 pt on the display holding its centre as `The previous area is not on a connected display.` It never writes `lastAreaRect`.
- The context menu is SwiftUI's `.contextMenu` on the card; Control-click is passed on to it by the drag view.

Not built, by decision: the synthetic window shadow, the layer-backed freeze backdrop, the `NSHostingView` context-menu fallback (and, if right-click or Control-click fails on the card, the `hitTest(_:)` override in `QuickAccessCardDragView` that the checklist names) and the file-promise drag-out fallback, each a follow-up only if Tim's checklist shows the failure it answers.

Observations from the checklist run are still to be written down here by Tim: the window-shadow probe (pass or fail, sizes) and the comparison with the system shot; the drag-out receiver table (accepted, name, whole, prompt) for Finder, Slack, Chrome, Safari, Mail, Messages and Notes; the freeze latency medians for one and two displays; and whether right-click and Control-click open the card's menu on every part of the card. None of the GUI checks had been run when this was written.

**Phase 6b (built).** Delivered 2026-10-21 on `phase-6b-polish`. The suite reads `Test run with 810 tests in 95 suites passed`; the hand checks are in `docs/testing/phase-6b-manual-checklist.md`. The build follows the text above, as amended in place, with these points:
- All-in-One Fullscreen dismisses the overlay first and captures the rect's display as Capture Fullscreen does (the overlay's windows and the cards excluded, the pointer from Show cursor, never the crosshair); Capture and Window are taken with the overlay up (`duringSelection: true`).
- All-in-One selecting: with a rect showing, a click outside it without a drag takes the window under the pointer or else keeps the rect; a drag outside starts a new rect; a new rect on another display clears the first. The Window button survives a resize, move, nudge or typed size of a window's rect and is dropped by a new drag or a preselect. A handle is within 6 pt of its edge; Return and keypad Enter capture; Command and Control combinations are ignored.
- All-in-One resize: a moving edge stops 4 pt short of the opposite one; the pointer is rounded to a whole point first, so the edges that are not dragged do not move on a half-point drag, and every result is whole points. With the lock, a corner takes the larger of the pointer's width and its height times the ratio, an edge sets its side and grows the other about the centre, and both stop at the display; the ratio kept is the rect's when the lock went on, or when a new rect was set while locked. Typed W and H grow the rect from its top-left corner and move it inside the display (W wins with the lock); the field shows the size the rect really has afterwards, after a clamped Return and after Escape alike. The lock is one value for every display's overlay, so it follows the selection across displays.
- All-in-One toolbar and start: 8 pt below the rect, above it, or inside its bottom edge, 8 pt inside the screen's sides and below the menu bar's safe area, hidden while a drag, resize or move runs. The start rect is a URL command's, else `lastAreaRect`, through `selectAllInOne(content:freeze:preselect:)`; a preselect does not write `lastAreaRect`.
- Focus loss corrects 2.9's Risks: no selection mode cancels when another app activates, and 6b adds none; the overlay stays up until Escape, Cancel or a choice. The key routing is tested through `SelectionAdjust.keyCommand`.
- Self-Timer: after the overlay is dismissed TidyShot gives up activation, so the user's app keeps its menus and keys. The badge is kept inside its screen and sits at the screen-saver level (`isFloatingPanel` is set before `level`, which it resets). At zero the shareable content is read again and the display or window found by id; the two strings are `The window is no longer on screen.` and `The display is no longer connected.`, titled `Self-timer`. A picked window does not write `lastAreaRect`. A stored `selfTimerSeconds` other than 3, 5 or 10 reads as 5. The shared Escape hotkey cancels whichever of the countdown and a scrolling session runs.
- Pin: the downsample is `ThumbnailMaker.scaled(_:maxSide:)` (2.9 named `thumbnail(from:maxSide:)`, which cuts a tall image to its top). A second Pin brings the first forward. `latestCaptureArea`, set in `save(_:intent:)`, places a pin over its capture. A pin opens without the keyboard and takes it on a click (`PinView.mouseDown` makes the panel key; the level is set after `isFloatingPanel` as for the badge). Zoom and Actual Size are whole points and stay within the pin's screen, so ⌘0 on a capture larger than the screen fits it. A strip under 40 pt keeps its short side as the floor. The status menu's pin items stay enabled during a capture. The failure titles are `Could not pin the capture`, `Pinning the capture…` and `The capture is too large to pin.`
- `CaptureIntent` carries `sender`, and `.standard` is read when the capture starts. Every URL notification carries `From <sender>` as its subtitle when the sender is known; `URLCommandGate.decision(for:enabled:allowSilent:sender:)` names it in the silent refusal. `Notifier.notifyError` and `notify` gain `subtitle:`. `AfterCaptureAction` is `nonisolated` and `Sendable`. `action=copy` plays the shutter sound and posts the pixel size as the body of `Image copied`.
- Two URL error strings were added: `“<name>” is given more than once.` and `The area leaves less than a point on display <n>.`
- URL numbers: a plain decimal of at most 16 characters and 100,000 pt; `display` 1 to 99, used only with a rect; values in messages lose control and format characters and are cut at 40 characters; names and actions match ignoring case after percent-decoding; with URL commands off even an unparseable URL gets the off message; at most 8 URLs wait for launch, and of those only the first capture command that passes the gate runs.
- `capture-scrolling` with a rect skips the selection and opens the session panel without activating TidyShot and without making the panel key (2.9 and the plan had it activate the app so Return is Start; a Return typed in the sender's frontmost app must not start a capture), so Start needs a click or the hotkey. Under 100 pt it is refused with the Phase 5 message. The rect is stored as `lastAreaRect` only when the stitched image is saved; a `capture-area` URL rect is stored once its capture succeeds (a failed capture leaves the stored rect as it was). Unstarted for 60 seconds, the preselected session cancels itself.
- An `all-in-one` URL command opened the overlay key with the start rect armed, so a Return typed in another app as the overlay appeared, or the second click of a double-click, captured the sender's rect with the sender's action and no silent-capture gate. Its start rect now opens disarmed until a press in the overlay or a toolbar control (All-in-One, Start); the hotkey and the menu are unchanged.
- Retention pruning closes the pruned records' pins (their menus pointed at a record that was gone) and forgets `latestCapture` and `latestCaptureArea` for them, as `removeRecord` does.
- The silent-capture caption in General ends `…can send them, and an allowed command lets the sending app read the result from the clipboard.`
- Release builds set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`: the Release app carries the four entitlements it had before (checked with `codesign -d --entitlements -`) and no `get-task-allow`; Debug keeps it for the tests and the debugger.
- Code structure: `URLCommandHandler` with the `URLCommandTarget` protocol and its own suite; `.cancelScrollingCapture` is `.cancelCapture` in code with the stored name unchanged; `SelectionController.init(engine:settings:cardWindowNumbers:)`; `CaptureTarget.cgFrame` and `areaRect`.
- Constants as built: All-in-One minimum side 4 pt, handle tolerance 6 pt, nudges 1 and 10 pt, toolbar gap and margin 8 pt; self-timer 3, 5 and 10 s (default 5), a 96 pt panel with 48 pt digits, a 2 pt dashed frame (the scrolling capture's), 100 ms before the capture; pins at least 40 pt on the short side, opacity 10 % to 100 % in 5 % steps with presets 100, 90, 75, 50 and 25 %, zoom steps of 10 %, a downsample above 8,192 px, an 80 % fit; URL numbers of at most 16 characters and 100,000 pt, displays 1 to 99, values cut at 40 characters, 8 URLs held before start. The new `AppSettings` keys and defaults are `allInOneAspectLock` (false), `selfTimerSeconds` (5), `urlCommandsEnabled` (true) and `urlCommandsAllowSilent` (false). The shortcuts are `allInOne` (⌃⇧1), `selfTimer` (none) and `cancelCapture` (stored as `cancelScrollingCapture`, Escape). The strings match 2.9.
- Fixes found in review that the tests pin: the opposite edges stay on half-point drags, the self-timer badge level, the pin zoom bounds and whole points, the queue's single capture command, All-in-One's disarmed URL rect (`SelectionViewArmingTests`) and the scrolling session's ready timeout (`ScrollCaptureSessionTests`) (see the plan's totals note for the commits).

Observations from the checklist run are still to be written down here by Tim: which bundle owns `tidyshot:` after the stale registrations are cleaned and which one a cold launch started (probe 4), the sender each source shows (Terminal's `open`, Raycast, Keyboard Maestro, Shortcuts, Safari, Chrome) and whether Chrome offers "Always allow", whether Return and Escape behave with All-in-One's fields, and the memory of the 65,536 px pin. None of the GUI checks had been run when this was written.

### 2.10 Phase 7b design: Capture Text and hiding desktop icons (2026-10-21)

**Scope and order.** Two P2 rows of the table in 2.1: text recognition with QR codes, as a new capture called Capture Text, and Hide desktop icons. They are independent and small, so they ship together as one PR on the branch `phase-7b-text-icons`. The Background tool and window-with-background share a compositing step and need their own UI; they are Phase 7c. Nothing in 7b adds an entitlement or a Swift package. The probe sources are in `docs/superpowers/research/phase-7b-probes/`.

**Probes (2026-10-21, Tim's Mac, one 2560 x 1440 pt display at 2x).**
- **Vision.** The Swift API (`RecognizeTextRequest`, `DetectBarcodesRequest`, macOS 15 and later) was run on a generated 1800 x 1000 px image at 2x.
  - Speed: text took 0.1 to 0.2 s and barcodes 0.01 to 0.4 s. The very first text request after a restart took 24 s while the system loaded its model; later processes were fast again.
  - Settings: accurate level, language correction on, automatic language detection.
  - What it read: "Ünïcödé café naïve", "$1,284.50" and "QX-993" read correctly. An em dash came back as a hyphen, and runs of spaces collapsed to one.
  - Same-line words: at 2x, two words on one line ("Column A" and "Column B") came back as two observations; at 1x they came back as one.
  - QR: a QR code holding `https://snap.tky.io/2BkqQ.png` was read exactly at 1x and 2x.
- **Window list.** The desktop is made of these windows, from the bottom up:
  - The wallpaper: one window per display, owned by `com.apple.WindowManager`, titled `Wallpaper`, at layer -2147483624, covering the display's frame.
  - Finder's icon window, at layer -2147483603 (`CGWindowLevelForKey(.desktopIconWindow)`).
  - A transparent `underbelly` window along the top 122 pt, at -2147483602.
  - Desktop widgets (`com.apple.notificationcenterui`), at -2147483601.
- **Wallpaper capture.** `SCContentFilter(desktopIndependentWindow:)` on the wallpaper window took 97 ms and returned 5120 x 2880 px. `NSWorkspace.desktopImageURL(for:)` returns `/System/Library/CoreServices/DefaultDesktop.heic`, a dynamic picture whose file does not match what is on screen, so the window capture is the source.
- **Cover.** A borderless window at `desktopIconWindow + 3`, showing the wallpaper capture, hid the icons and widgets in a ScreenCaptureKit display capture 16 ms after `orderFrontRegardless()`. The mean pixel difference to the wallpaper was 0.0, against 10.3 over the widgets without the cover.

#### Capture Text

**Entry points.**
- Status menu: `Capture Text  ⌃⇧7`, after `Self-Timer`.
- Shortcut recorder: `Capture text:` (⌃⇧7), last of the capture recorders, before `Restore closed overlay:`.
- URL command: `tidyshot://capture-text`.

**Selection.** It uses Capture Area's overlay (`selector.select(mode: .area, content:freeze:)`), and Freeze screen applies as it does there. The image is what Capture Area would have captured:
- the frozen crop, or a live capture with the overlay excluded and no pointer (`duringSelection: true`);
- or the clicked window, when the overlay returns `.window` (area mode never does; see the Built notes).

The overlay is dismissed after the capture. Capture Text does not write `lastAreaRect`, because the previous area is for image captures. The capture lock is held for the selection and the capture only and is released before recognition, so the 24 s first run never blocks other captures.

**Recognition.** `TextRecognizer.recognize(_:)` is `@concurrent` and runs off the main actor.
- Text: `RecognizeTextRequest` with `recognitionLevel = .accurate`, `usesLanguageCorrection = true` and `automaticallyDetectsLanguage = true`, keeping the top candidate of each observation.
- Codes: `DetectBarcodesRequest` with `symbologies = [.qr, .microQR, .aztec, .dataMatrix, .pdf417]`. Two-dimensional codes only, because stripes in a screenshot can read as one-dimensional barcodes. Payloads that are nil or empty are dropped.
- The result is a value type `TextScan { pieces: [TextPiece], codes: [CodePiece] }`. Each piece keeps its string, its symbology for codes, and its normalised bounding box (origin at the bottom left, as Vision gives it).

**Joining text** (`TextJoiner.join(_:)`, pure). Vision's order is kept, because it already follows columns.
- A piece continues the previous piece's line, joined by one space, when both of these hold:
  - its vertical overlap with the previous piece is at least half the smaller of the two heights;
  - its left edge is at or right of the previous piece's right edge, minus 0.01.
- Otherwise it starts a new line, joined by `\n`.
- Pieces that are empty after trimming are skipped, and the result is trimmed.

**Outcome** (`TextCaptureOutcome.decide(_:)`, pure).
- **Codes.** One or more codes win. The clipboard gets their payloads in Vision's order, exact duplicates once, joined by `\n`. The text is dropped, so selecting a QR code with "Scan me" under it gives a link that pastes cleanly. To get the text, select without the code.
- **Text.** Otherwise, the joined text when it is not empty.
- **Nothing.** Otherwise there is nothing to copy.

**Clipboard.** `NSPasteboard.general.clearContents()`, then `setString(_:forType: .string)`. Capture Text makes no file, record, card or upload, ignores the after-capture action, `CaptureIntent` and Clop, and leaves the clipboard untouched when nothing was found. `clipboardOwner` is left alone: the clipboard's change count moved, so no editor save replaces the text.

**Feedback.**
- **Sound.** With Play sound on, the capture sound plays when something was copied.
- **Notifications.** These follow Show notification:
  - Text: title `Text copied`, body the text's first line, cut to 80 characters plus `…`.
  - One QR or Micro QR code: title `QR code copied`; another single code: `Code copied`; several codes: `<n> codes copied`. The body is the first payload, cut the same way.
  - A single payload that is an `http` or `https` URL with a host carries the URL, so clicking the notification opens it in the default browser, as the upload notification does. No other payload opens anything.
- **Always posted.**
  - Nothing found: title `No text found`, body `TidyShot found no text or QR code in the selection.`
  - Vision throws: title `Text not recognized`, body the error's description.

**URL command.** `capture-text` takes `x`, `y`, `width`, `height` and `display`, like `capture-area`, and no `action`.
- Without a rect it opens the selection.
- With a rect it reads that rect at once, live, with the cards excluded and no pointer. That counts as capturing without a selection, so it also needs Allow URL commands that capture without a selection.
- The sending app can read the result from the clipboard, as the silent-capture caption already says.

**Deferred.** Recognising text in an existing capture (card, Recent Captures, editor); a Text button in All-in-One's toolbar; a language setting; joining wrapped lines into paragraphs; opening payloads that are not web links.

#### Hide desktop icons

**Two ways to turn it on.**
- **While capturing.** A Capture tab setting, `Hide desktop icons while capturing` (off). With it on, the desktop is covered for the whole run of Capture Area, Capture Window, Capture Fullscreen, All-in-One, Capture Previous Area and Self-Timer (countdown included), and of the URL commands that start them, and of area and fullscreen recordings (see the recording design: the covers stay up for the whole recording and are in the video; a window recording hides them once the window is chosen, because it shows only the window). That is from before the shareable content is read, so freeze snapshots and window lists see the covers, until the capture flow ends.
  - Not Capture Scrolling: the covers would stay up for a whole session.
  - Not Capture Text: covering adds about 100 ms per display for nothing visible.
- **Until turned off.** A status menu item `Hide Desktop Icons`, with a checkmark while on. Its state is stored as `desktopIconsHidden` (false) and restored at launch. The URL commands `hide-desktop-icons`, `show-desktop-icons` and `toggle-desktop-icons` (CleanShot's names) set the same state. They capture nothing, so Allow URL commands alone is enough; they take no parameters.

**Covers.** `DesktopCoverPanel` is an `NSPanel` subclass with `.borderless` and `.nonactivatingPanel`, one per display:
- Frame: the display's `NSScreen` frame.
- Level: `CGWindowLevelForKey(.desktopIconWindow) + 3`, above Finder's icons and the widgets and below every normal window.
- Appearance: opaque, no shadow, `canBecomeKey` and `canBecomeMain` false.
- Behaviour: `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`.
- Content: a layer whose `contents` is the wallpaper image with `contentsGravity = .resize`.

The covers take mouse events and do nothing with them, so the hidden icons cannot be opened or dragged by a click that lands on them. While the desktop is hidden, clicking the wallpaper does not reveal the desktop, and the desktop's context menu does not open. The covers are not excluded from captures: an area or fullscreen capture shows the wallpaper where the icons were. `WindowPicker` already ignores windows whose layer is not 0.

**Wallpaper.** `WallpaperMatcher.match(_:displayFrame:)` is pure and works on value candidates (window id, bundle id, title, layer, frame). For each display it picks:
1. the window owned by `com.apple.WindowManager`, titled `Wallpaper`, whose frame equals the display's frame;
2. otherwise the lowest-layer `com.apple.WindowManager` window whose frame equals the display's frame;
3. otherwise none.

`WallpaperSource` captures each display's match with `SCContentFilter(desktopIndependentWindow:)`, at the frame times the display's scale and without the pointer. The displays are captured concurrently. A display with no match, or whose capture fails, gets no cover. One notification per app session reports it: title `Desktop icons still showing`, body `TidyShot could not read the desktop picture.`

**Timing.** `DesktopCoverController.show(for:) async` captures the wallpapers, orders the panels front, flushes with `CATransaction.flush()`, then waits 50 ms before returning; the probe saw the cover in a capture after 16 ms. `hide(for:)` orders them out at once. The controller keeps a set of reasons (`.capture`, `.persistent`, in the pure `DesktopCoverReasons`), and the covers show while the set is not empty. A capture flow that ends removes `.capture` and leaves a persistent cover up.

**Refresh while on.** The wallpaper is captured again, and each cover's contents swapped, on:
- `NSWorkspace.activeSpaceDidChangeNotification` (each Space can have its own wallpaper);
- `NSApplication.didChangeScreenParametersNotification` (panels are rebuilt for the current displays);
- `NSWorkspace.didWakeNotification`;
- every 10 minutes (dynamic wallpapers change through the day).

Capturing the wallpaper window alone is not affected by the covers above it. After a Space switch, the cover shows the previous Space's wallpaper until the refresh completes, about 100 ms later.

#### Settings summary

- **Capture:** `Hide desktop icons while capturing`, captioned `Covers desktop icons and widgets with the desktop picture during area, window, fullscreen, previous-area, All-in-One and self-timer captures, and area and fullscreen recordings. While covered, the desktop does not take clicks.` (the recording R1 text; it was `…self-timer captures.` in 7b), after `Include window shadow`.
- **Shortcuts:** `Capture text:` (⌃⇧7).
- **New `AppSettings` keys:** `hideDesktopIconsWhileCapturing` (false) and `desktopIconsHidden` (false). New shortcut: `captureText` (⌃⇧7).

**Status menu after 7b.** `All-in-One`, `Capture Area`, `Capture Window`, `Capture Fullscreen`, `Capture Scrolling`, `Capture Previous Area`, `Self-Timer`, `Capture Text  ⌃⇧7`; separator; Recent Captures, `Restore Closed Overlay`, Retry Failed Uploads, Reveal Last Capture, `Hide Desktop Icons` (checkmark); separator; the pin items, Settings…, Quit TidyShot. Capture Text is disabled while a capture runs, like the other capture items. `Hide Desktop Icons` is always enabled.

**Architecture.** New files:
- `TidyShot/Text/`: `TextRecognizer.swift` (Vision), `TextScan.swift`, `TextJoiner.swift` (pure), `TextCaptureOutcome.swift` (pure: the decision and the notification wording).
- `TidyShot/Desktop/`: `DesktopCoverController.swift`, `DesktopCoverPanel.swift`, `WallpaperSource.swift`, `WallpaperMatcher.swift` (pure), `DesktopCoverReasons.swift` (pure).

Edits:
- `AppCoordinator`: `captureText(intent:)`, `captureText(at:)`, the covers in the capture flows, `setDesktopIconsHidden(_:)`.
- `URLCommand` (four kinds), `URLCommandHandler` and `URLCommandTarget`.
- `Notifier`: an optional URL to open on click.
- `Shortcuts`, `StatusMenuController`, `CaptureSettingsView`, `ShortcutsSettingsView`, `AppSettings`.

The 2.6 concurrency rule holds: Vision and the wallpaper captures run `@concurrent`, and the panels and controller are MainActor.

**Tests (Swift Testing).**
- `TextJoinerTests`:
  - two pieces on one line joined by a space;
  - lines joined by a newline;
  - a piece left of the previous one on an overlapping band starts a new line;
  - empty pieces skipped;
  - the result trimmed;
  - a single piece.
- `TextCaptureOutcomeTests`:
  - codes win over text;
  - a duplicate payload kept once;
  - an empty payload ignored;
  - text only;
  - nothing;
  - each notification title, including `QR code copied`, `Code copied` and `3 codes copied`;
  - the body cut at 80 characters with `…`, first line only;
  - the URL to open only for a single `http`/`https` payload with a host (not `javascript:`, `file:` or `mailto:`).
- `TextRecognizerTests`: real Vision on a generated 2x image with a line of text and a QR code. The text contains the line, and the code's payload is exact. The time limit is 2 minutes, for the cold model.
- `WallpaperMatcherTests`:
  - the titled match;
  - a second display;
  - the untitled fallback;
  - another display's wallpaper ignored;
  - no match.
- `DesktopCoverReasonsTests`:
  - capture and persistent together;
  - the end of a capture leaves persistent;
  - persistent off during a capture keeps the covers until the capture ends.
- `URLCommandTests`:
  - `capture-text` with and without a rect, and its silent rule;
  - the three desktop-icon commands parse, take no parameters, and need only URL commands on.
- `URLCommandHandlerTests`: the four routes.
- `AppSettingsTests`: the two keys' defaults and persistence.

The hand checks go in `docs/testing/phase-7b-manual-checklist.md`.

**Phase 7b (built).** Delivered 2026-10-21 on `phase-7b-text-icons`. The suite reads `Test run with 897 tests in 104 suites passed`; the hand checks are in `docs/testing/phase-7b-manual-checklist.md`. No entitlement and no package were added. The build follows the text above, with these points:
- Capture Text's area overlay never returns a window (area mode has no window picker), so a click without a drag cancels, as in Capture Area; the `.window` case in `captureText()` is only there to keep the switch exhaustive.
- Scrolling captures are not covered: `ScrollFrameSource.makeFilter` excludes TidyShot's whole app, which takes the covers out of the picture, so with Hide Desktop Icons on, a scrolling capture over the desktop shows the icons in the stitched image.
- `hide(for:)` drops the panels with the covers, which frees the wallpaper images (about 59 MB per 5K display); a show from hidden captures every screen again anyway.
- Architecture: Capture Text is `AppCoordinator.captureText()`, not `captureText(intent:)`, because it ignores `CaptureIntent`; the URL handler computes an intent for every command and does not pass it here. `captureText(at:)` captures with `duringSelection: true`, so the pointer is never in it, whatever Show cursor says. Both release the capture lock before recognition (`copyText(in:)`). `areaResult` now stores the previous area and calls the new `selectedAreaResult`, the frozen-or-live part that Capture Text shares without writing `lastAreaRect`.
- `URLCommand.Kind` has four new cases. `isCapture` now means only "dropped while a capture runs", and a new `takesAction` decides whether `action` is read. `capture-text` is a capture and has `isCapture` true, so it is dropped while a capture runs; only its `takesAction` is false, so `action` is ignored. `restore-recently-closed` and the three desktop-icon commands have both false: `action` is ignored and they run while a capture runs, as restore does.
- `URLCommandTarget` gains `captureText()`, `captureText(at:)`, `setDesktopIconsHidden(_:)` and `toggleDesktopIconsHidden()`. A queued `capture-text` before launch is awaited through its recognition, so a later queued URL can wait for the cold 24 s model load; a hotkey or menu capture is never held up.
- Outcome details 2.10 left open: duplicate and empty payloads are dropped before the title and `openURL` are chosen, so two identical QR codes give `QR code copied` and a link that opens; a single code's title follows its symbology (QR and Micro QR `QR code copied`, others `Code copied`); the preview trims, takes the first line and adds `…` only when that line is longer than 80 characters. In the join, each piece is trimmed, and an empty piece is skipped and never becomes the previous piece. `Notifier.notify(title:body:subtitle:openURL:)` stores the URL under the key `notifyUploaded` uses.
- Covers: a new pure `DesktopCoverPlan` (`make(screens:covered:captured:kind:)`, the kind being a show from hidden, a show while up or a refresh, and `needingCapture(screens:covered:)`) decides which panels get a new wallpaper, which are removed and which displays are reported. A refresh whose capture fails for a display keeps that display's last wallpaper while the covers show (2.10 says such a display gets no cover; that holds for a display that never had one and for any show from hidden). A cover is dropped only when its display is gone. A `show` while the covers are up covers any screen that has none, sharing a capture in flight. A refresh that arrives while a capture is in flight sets a flag, and one more capture runs and is applied when that capture ends with the covers still showing, so two quick Space switches or a display not yet listed are not left on the earlier capture. The panels are kept after a hide, but a show from hidden treats them as uncovered: each gets the new wallpaper or goes, and a display left without one is reported. The refresh observers and timer run only while the covers show.
- `WallpaperSource` reads `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` and captures each match in a task group with `ignoreShadowsSingleWindow`; `SCWindow` crosses into the child task as a `nonisolated(unsafe)` constant, the first use of that pattern in the code base. The panel also sets `hidesOnDeactivate = false` and `animationBehavior = .none`, and its view swallows the left, right and other mouse buttons and returns no menu.
- Wiring: the coordinator owns one `DesktopCoverController`, so "one notification per app session" is the controller's at-most-once `reportFailure`; it is posted with `notifyError`, so always, like the other failure notices. When Screen Recording is not granted, the coordinator's `reportFailure` shows the permission window instead of posting `Desktop icons still showing`. `withCaptureLock(coversDesktop:_:)` takes the lock, then with `coversDesktop` and the setting on awaits `show(for: .capture)` before the body and calls `hide(for: .capture)` after it; the capture items are disabled during the bring-up. Capture Scrolling and both Capture Text paths pass false. All-in-One's Scrolling button removes `.capture` before the scrolling session, as Capture Scrolling would never have covered it. `setDesktopIconsHidden(_:)` stores `desktopIconsHidden` first, then shows or hides the persistent covers; `start()` shows them when it is stored on. The menu item's checkmark reads `desktopIconsHidden`.
- The silent-capture caption in General now names `capture-text` with a rect, which the gate treats the same: it starts `capture-fullscreen, capture-previous-area, and capture-area or capture-text with x, y, width and height capture at once.`, and 2.9 quotes it so.
- Tests as listed above, plus: `DesktopCoverPlanTests` (10), `ShortcutsTests.captureTextIsControlShiftSeven`, the join rule at its two boundaries, the URL rule for `file:`, `mailto:` and a URL without a host, and the handler running the desktop-icon commands while a capture runs and refusing them with URL commands off.

Observations from the checklist run are still to be written down here by Tim: the cold first-run time of Capture Text, what two columns and a non-Latin script came back as, how long the covers take to appear and when a wallpaper change reaches them, and how the failure notification was checked. None of the GUI checks had been run when this was written; Task 3 ran a scratch harness on Tim's Mac (one 5120 x 2880 wallpaper captured in about 120 ms, one cover at layer -2147483600, the reasons behaving as specified).

### 2.11 Phase 7c design: backgrounds (2026-10-21)

**Scope.** This covers the last two P2 rows of the table in 2.1, Background tool and Window with background:
- **Editor.** A Background tool in the editor puts a capture on a background, with padding, rounded corners, a shadow and an aspect ratio.
- **Capture setting.** A Capture-tab setting does the same to every window capture as it is taken.

Both use one compositor and one style type. The work happens on the branch `phase-7c-background`, cut from `phase-7b-text-icons` because it reuses 7b's `WallpaperSource`; its PR targets that branch until 7b merges. There is no new entitlement or package; a custom background image is read through the open panel's user-selected access, which the app already has. Deferred: CleanShot's auto-balance, alignment other than centred, more than one custom image, and saving a style as a named preset.

**Probe** (2026-10-21; source `docs/superpowers/research/phase-7c-probes/comp.swift`). The probe drew a two-stop gradient, then the capture clipped to a rounded rectangle inside a transparency layer with a CoreGraphics shadow (blur 48 px, offset 16 px), with 128 px of padding.

| Capture | Time |
|---|---|
| 1600 x 1000 | 32 ms |
| 5120 x 2880 | 139 ms |
| 3094 x 16000 | 442 ms |
| 3094 x 65536 | 1.9 s, several GB of memory |

The shadow follows the image's alpha, so a window capture's own rounded corners cast a correctly shaped shadow. Backgrounds are therefore limited to content up to 16,384 px on its long side.

#### Style

`BackgroundStyle` (nonisolated, `Codable`, `Equatable`, `Sendable`). Every field decodes with `decodeIfPresent` and falls back to its default.
- `fill: BackgroundFill`. The cases:
  - `.gradient(Int)` holds an index into `BackgroundPresets.gradients`; an index out of range draws preset 0.
  - `.solid(RGBA)`.
  - `.desktopPicture` uses the wallpaper of the display concerned, captured through 7b's `WallpaperSource`.
  - `.customImage` uses the one stored custom image.
  - The default is `.gradient(0)`.
- `padding: Double`, in points, 0 to 160, default 48.
- `cornerRadius: Double`, in points, 0 to 40, default 12.
- `shadow: Bool`, default true.
- `aspect: BackgroundAspect`: `.auto` (default), `.square`, `.fourThree`, `.threeTwo`, `.sixteenTen`, `.sixteenNine`. Titles: `Auto`, `1:1`, `4:3`, `3:2`, `16:10`, `16:9`.

**Gradients.** `BackgroundPresets.gradients` holds twelve two-stop linear gradients. Each is drawn from the top-left corner (first colour) to the bottom-right corner (second colour) of the whole background:

| # | Name | First | Second |
|---|---|---|---|
| 0 | Sunset | `#FF7A59` | `#7B4DFF` |
| 1 | Ocean | `#1FA2FF` | `#A6FFCB` |
| 2 | Grape | `#8E2DE2` | `#4A00E0` |
| 3 | Peach | `#FFD3A5` | `#FD6585` |
| 4 | Mint | `#43E97B` | `#38F9D7` |
| 5 | Midnight | `#232526` | `#414345` |
| 6 | Sky | `#A1C4FD` | `#C2E9FB` |
| 7 | Flamingo | `#F857A6` | `#FF5858` |
| 8 | Forest | `#134E5E` | `#71B280` |
| 9 | Lemon | `#F9F586` | `#96FBC4` |
| 10 | Slate | `#8E9EAB` | `#EEF2F3` |
| 11 | Berry | `#C471F5` | `#FA71CD` |

**Layout** (`BackgroundLayout.make(contentSize:style:scale:) -> BackgroundLayout?`, pure, in pixels). Content is the flattened capture, or its crop.
- `pad = round(padding × scale)`. The minimum canvas is the content plus `2 × pad` on each axis.
- For an aspect other than `.auto`, the ratio is width:height, and is inverted when the content is taller than wide. The minimum canvas grows along one axis, never shrinks, until it has that ratio, rounded up to whole pixels.
- The content is centred and its origin rounded down to whole pixels.
- Returns `canvasSize` and `contentRect` (top-left origin).
- Returns nil when the content's long side is over `BackgroundLayout.maximumContentSide` (16,384), or when the canvas would be over 32,768 px on a side.
- `radius = cornerRadius × scale`, capped at half the content's shorter side.

**Compositing** (`BackgroundCompositor.compose(_ content: CGImage, style:scale:fillImage:) -> CGImage?`, nonisolated, CoreGraphics only, no NSGraphicsContext). It makes an 8-bit premultiplied RGBA bitmap in sRGB at `canvasSize`, then:
1. **Fill.**
   - A gradient fills the whole canvas, drawn from its top-left corner to its bottom-right corner.
   - A solid colour fills it flat.
   - `fillImage` (a desktop picture or the custom image) is drawn aspect-fill and centred.
   - When `fillImage` is nil for those two fills, preset 0 is drawn instead.
2. **Shadow.** With `shadow` on, the compositor sets a shadow (`offset (0, -8 × scale)`, `blur 24 × scale`, black at 35%) and opens a transparency layer. The next step draws inside it, then the layer ends.
3. **Content.** The content is clipped to the rounded rect (`contentRect`, `radius`) and drawn at its pixel size, with interpolation off.

The output's scale is the content's. A window capture's transparent corners stay transparent inside the clip, so the fill shows through them. Compose returns nil when the layout is nil or no bitmap can be made. The caller then keeps the content without a background and says so (below).

**Fill images.**
- **Desktop picture.** `BackgroundFillSource.desktopPicture(displayID:) async -> CGImage?` uses `WallpaperSource`. For a window capture, the display is the captured window's. In the editor it is the display under the editor window.
- **Custom image.** `CustomBackgroundStore` keeps one file, `Application Support/TidyShot/Backgrounds/custom.png` in the container.
  - The style editor's `Choose Image…` opens an `NSOpenPanel` for images (`UTType.image`).
  - The chosen file is decoded, scaled down to at most 6,000 px on its long side, and written as PNG over the previous one.
  - An image that cannot be decoded posts `Not a usable image` with the file name, and nothing changes.
  - When the file is missing, `.customImage` draws preset 0.

#### Style editor

`BackgroundOptionsView` (SwiftUI) is used in two places: the editor's Background popover and the Capture tab's style sheet. From top to bottom:
1. A swatch grid of 15 fills, five per row: the twelve gradients in order (tool tip: the gradient's name), then `Desktop Picture`, then `Solid Colour` (a `ColorPicker` swatch), then `Custom Image`. The custom swatch shows the stored image, or a `photo` symbol with `Choose Image…` when there is none; once one is stored, a small `Choose Image…` button replaces it.
2. Padding: a slider from 0 to 160 pt, labelled `Padding` with the value in points.
3. Corners: a slider from 0 to 40 pt, labelled `Corner Radius`.
4. A `Shadow` toggle.
5. A picker labelled `Aspect Ratio` with the six titles.

The selected swatch has an accent ring. The view takes a `Binding<BackgroundStyle>` and calls `onCommit` at the end of each slider drag and on every other change. A slider drag shows live, but makes one undo step in the editor.

#### Editor

- **Model.** `AnnotationDocument.background: BackgroundStyle?` is nil for none and decoded with `decodeIfPresent`. It is changed through `EditorModel.commit`, so it is undoable: the toggle, each swatch choice, each slider drag and each picker change is one step.
- **Toolbar.** A `Background` button item (`rectangle.inset.filled`, tool tip `Background`) goes after Options. It opens a popover whose first row is a `Background` toggle, with `BackgroundOptionsView` below it. Turning the background on starts from the Capture tab's style (`AppSettings.backgroundStyle`). Turning it off sets nil and keeps nothing.
  - When the content is too large (`BackgroundLayout.make` returns nil), the toggle is disabled and captioned `Backgrounds work on images up to 16,384 px.`
  - The window's minimum width is measured again, so nothing overflows (2.6 feedback rule).
- **Preview.** `BaseImageView` gains three layers, placed by the transform like the image layers:
  - a background layer behind the image, at `contentRect` mapped back into image coordinates, so it extends past the image by the padding. Its contents are the fill only, rendered off the main actor at most 2,048 px on the long side whenever the style, the crop or the display changes;
  - a shadow layer (`shadowPath` the rounded content rect, the same colour, opacity, offset and blur in view points);
  - a rounded mask over a container holding the image and effect-tile layers.

  `CanvasView` clips its drawings to the same rounded rect while a background is on. "Zoom to fit" fits the whole canvas. Annotations stay in image coordinates; the padding is not drawn on. While the Crop tool is active, the preview is hidden and fit uses the image, so the crop handles work as in 4b. The background frames the applied crop.
- **Export.** `EditorModel.renderExport` flattens as now, crop included. When `document.background` is set, it then resolves the fill image (desktop picture for the editor's display, or the custom image) and composes, off the main actor, before returning the `ScaledImage`. Save, Save As…, Copy and Upload all get the composed image. The record's thumbnail follows from the saved file as now. If compose fails, the export fails like any other export (`Not saved` or `Not uploaded`, with `The background could not be drawn.`), and the editor stays dirty.

#### Window captures

- **Setting.** The Capture tab gets `Add background to window captures` (`AppSettings.windowBackground`, default false), captioned `Puts each window capture on the background below, as the editor's Background tool would.` and followed by an `Edit Background…` button. The button opens a sheet on the Settings window with `BackgroundOptionsView` bound to `AppSettings.backgroundStyle` (stored as JSON under `backgroundStyle`, default `BackgroundStyle()`) and a `Done` button. The editor's Background tool starts from the same style.
- **When.** In `AppCoordinator.save(_:intent:)` (so for Capture Window, All-in-One's Window, a Self-Timer window and `capture-window`, including `action=copy`), when the result's target is `.window` and the setting is on, the image is replaced by the composed one before encoding. The desktop picture is the window's display's. Composing runs detached at `.userInitiated`. If it fails, the capture keeps the plain window image and logs `Background: <reason>, keeping the window capture`. No notification is posted, because a capture is never lost.
- **Not included.** Area, fullscreen, scrolling and previous-area captures. For those, use the editor's Background tool.

#### Settings summary

- **Capture tab:** `Add background to window captures`, its caption and `Edit Background…`, after `Hide desktop icons while capturing`.
- **New `AppSettings` keys:** `windowBackground` (false) and `backgroundStyle` (JSON, the default style).

**Architecture.** New files:
- `TidyShot/Background/`: `BackgroundStyle.swift` (with `BackgroundFill` and `BackgroundAspect`), `BackgroundPresets.swift`, `BackgroundLayout.swift` (pure), `BackgroundCompositor.swift`, `BackgroundFillSource.swift`, `CustomBackgroundStore.swift`, `BackgroundOptionsView.swift`, `BackgroundStyleSheet.swift`.

Edits: `AnnotationDocument`, `EditorModel` (export), `EditorToolbar` and `EditorWindowController` (item, popover, minimum width), `BaseImageView` and `CanvasView` (preview, clip, fit), `CaptureSettingsView`, `AppSettings`, and `AppCoordinator.save`.

**Tests (Swift Testing).**
- `BackgroundStyleTests`:
  - the defaults;
  - a JSON round trip;
  - an empty JSON object decodes to the defaults;
  - an out-of-range preset index draws preset 0 (through the compositor);
  - an `AnnotationDocument` without `background` decodes to nil.
- `BackgroundPresetsTests`: twelve presets, unique names, the table's hex values for 0 and 11.
- `BackgroundLayoutTests`:
  - padding at 1x and 2x;
  - each ratio growing the right axis;
  - a portrait content inverts the ratio;
  - content already wider than 16:9 grows its height;
  - odd sizes centre with the origin rounded down;
  - the radius cap;
  - nil above 16,384 px.
- `BackgroundCompositorTests`:
  - the output size equals the layout's;
  - a solid fill's corner pixel equals the fill;
  - a content pixel equals the content;
  - a pixel just inside the content's corner, outside the rounded clip, equals the fill (shadow off);
  - with shadow on, a pixel just below the content is darker than the fill;
  - a transparent content corner shows the fill;
  - nil above the limit;
  - a nil fill image draws preset 0.
- `CustomBackgroundStoreTests` (a temporary directory):
  - store, replace, scale-down of a large image;
  - an undecodable file is refused;
  - the image is read back.
- `AppSettingsTests`: the two keys.
- `EditorFlattener` export with a background (through `EditorModel.renderExport` on a test model): the canvas size and a fill pixel.

The hand checks go in `docs/testing/phase-7c-manual-checklist.md`.

**Phase 7c (built).** Delivered 2026-10-21 on `phase-7c-background`. The suite reads `Test run with 955 tests in 110 suites passed`; the hand checks are in `docs/testing/phase-7c-manual-checklist.md`. No entitlement and no package were added. The build follows the text above, with these points:
- Background folder: `BackgroundAspect` also has `title`, `ratio` and `terms`, the ratio as whole numbers, so the layout rounds with integer maths. `BackgroundLayout` has a second limit constant, `maximumCanvasSide` (32,768), returns nil for empty content, and floors negative padding and radius at 0. `BackgroundCompositor` gained `fill(_:size:fillImage:)`, the fill alone, which the editor's preview uses and which shares `drawFill` with `compose`; its shadow constants are internal. The layout is top-left, so the compositor flips y for CoreGraphics. `RGBA.init(hex:)` is new, for the presets. `CustomBackgroundStore` has a `preview(maxSide:)` for the swatch, and a failure to write after a good decode is logged, not posted, since `Not a usable image` would mislead.
- Settings: a corrupt `backgroundStyle` value, or one with a fill or aspect from a newer build, reads as the default style.
- Style editor: once an image is stored, the small `Choose Image…` button sits under the grid and the custom swatch shows the image (2.11 said the button replaces the symbol). `BackgroundOptionsView(style:onCommit:onUnusableImage:)` takes a third, required closure that receives the file name; the Settings sheet and the editor route it to `AppCoordinator.notifyUnusableBackgroundImage(named:)`, which posts `Not a usable image`. The Solid Colour swatch shows the style's own colour. `CustomBackgroundRevision.shared` counts stored images; the swatch and the editor's preview fill key on it, so choosing another image while `.customImage` is already the fill refreshes both.
- Editor model: `renderExport` is `async throws(EditorExportFailure)`, with `.missingTile`, `.flatten` and `.background`; only `.background` has a message, `The background could not be drawn.`. `EditorActions` gained `exportFailed(message, title)` and `unusableBackgroundImage(fileName)`. The titles are `Not saved` (Save, Save As…), `Not uploaded` (Upload, Upload as New) and, for Copy, `Could not copy image`, which 2.11 left unnamed. `export()` commits a pending background draft first. `EditorModel.backgroundDraft` holds the live style during a slider drag (not in the document or undo), `setBackground(_:)` is the toggle, `commitBackgroundDraft()` the popover's `onCommit`, and `shownBackground` the layout in image pixels, nil while the Crop tool is open. Every step is under the action name `Background`. A commit that changes only a `.solid` fill uses the coalescing key `Background Colour`, so a run of colour changes with nothing else between them is one undo step, even across popover sessions.
- Popover: `BackgroundPopoverView` (new, beside `ToolOptionsView`) holds the switch and the options. The switch is disabled while off when the content is over the limit. `.onDisappear` commits a draft, so a drag cut short by the popover closing is still one step. `showPopover` closes the other popovers and the other way round. The toolbar's minimum width is 1062 pt (see 2.6).
- Preview: `BaseImageView`'s root layer holds a background layer, a shadow layer and a content layer, which carries the image and effect tiles and the rounded mask. The shadow layer has no contents: `shadowPath` is the rounded rect, `shadowRadius` is half the compositor's blur (a probe confirmed a layer's radius is half CoreGraphics' `blur`), and the layer is moved down by the offset rather than using `shadowOffset`, which the flipped layer tree would reverse. The preview's shadow follows the rounded rect, while the export's follows the capture's alpha, so they differ slightly for a window with transparent corners. `CanvasView` skips the crop cover while a background shows, since the mask hides the area, and `fitRect` is the whole canvas. The fill is rendered in a detached task, cached per fill, display and custom revision, and re-rendered when the editor window changes screen. An offscreen render of the preview showed no shadow while the export had one; the preview's shadow is a hand check.
- Window captures: `AppCoordinator.withWindowBackground` runs first in `save(_:intent:)`, so even the `copyOnly` branch gets the composed image. The log reasons are `the window is too large for a background` and `no bitmap could be made`. A desktop-picture fill adds one `WallpaperSource().wallpapers(only:)` call for the one display; its cost is a hand check.
- If undo restores a capture over 16,384 px while a background is on, the preview hides and the export fails with `The background could not be drawn.`, as 2.11 says.
- Tests as listed above, plus: `BackgroundLayoutTests` canvas-limit boundary and content ratio cases, gradient direction and shadow offset in the compositor tests, `EditorBackgroundExportTests` (crop then background, the undo steps, colour coalescing, the preview layers' frames) and `fillAloneHasTheSizeAndTheFill`.

Observations from the checklist run are still to be written down here by Tim: whether the preview's shadow matches the export's, whether the colour panel keeps working from the popover, how a drag cut short by the popover closing behaves, the time to follow the editor window to a second display, a desktop-picture window capture's time, and how Include window shadow looks under a background. None of the GUI checks had been run when this was written.

### 2.12 Phase 4c design: Spotlight and Counter (2026-10-22)

**Scope.** These are the two tools deferred from the 2.1 Annotate row and the Phase 4c list.
- **Spotlight** dims everything outside one or more rectangles or ellipses.
- **Counter** drops numbered circles (1, 2, 3, …) for step-by-step shots.

The rest of 4c stays deferred: the editable project format, and "open editor" as an after-capture action, which waits on Tim's open question about stale uploads. Work happens on the branch `editor-4c`, stacked on `recording-r1`, and its PR targets that branch. There are no new entitlements, packages or settings keys beyond the editor defaults below.

This section amends 2.6 in four places, each stated where it applies: the hit order (Select row), the accessibility order, the paste cascade's "identical apart from its id", and the Export rule that pixels outside the effects equal the base.

#### Spotlight

- **Tool.** `EditorTool.spotlight`: letter `S`, title `Spotlight`, symbol `light.max`, tool tip `Spotlight (S)`. It sits in `toolbarOrder` after Blur and before Rectangle, because it works on the picture as the effects do. It is not an effect (`isEffect` false), so it never gets a tile from `RedactionRenderer`. `makeTool(for:)` gives it `RectDragTool(tool: .spotlight)`.
- **Model.**
  - **Annotation.** `Annotation.spotlight(SpotlightShape)`, where `SpotlightShape { id: UUID; rect: CGRect; isEllipse: Bool }`, with the rect in image pixels and a top-left origin. It has no colour and no line width.
  - **Document.** `AnnotationDocument` gains `spotlights` (creation order), and `drawings` leaves them out, so `EditorFlattener` and `CanvasView` draw the overlay from `spotlights` and never in the drawings loop. `AnnotationDrawing.draw` draws nothing for a spotlight.
  - **Dim.** `AnnotationDocument.spotlightDim: Double?` (`decodeIfPresent`, nil reads as 0.5, and 0.5 is stored as nil) is the black overlay's opacity, one value for the whole document. It is shared because the overlay is a single layer with a hole per spotlight.
  - **Kind.** The accessibility kind name is `Spotlight`.
- **Drawing.** A drag draws the shape's rect, as Rectangle and Ellipse do, with Shift for a square or circle. The minimum side is the same as Rectangle's. `makeAnnotation` sets `isEllipse` from `spotlightEllipse`.
  - The shape's outline is never drawn into the image. While the Spotlight tool is active, the canvas shows a 1 pt dashed outline (white under black dashes, as `drawSelection` draws) around every displayed spotlight, the one being drawn included. A selected spotlight gets the selection outline and its 8 handles (Shared, Selection chrome). Both are chrome and never exported.
  - The tool's outlines are drawn in `CanvasView.draw(_:)` in view space, after the crop cover, in the step that draws the selection, so none are drawn while the Crop tool shows its chrome. They are not clipped to an applied crop, as the selection outline is not.
- **Rendering.** In both the canvas and `EditorFlattener`:
  - **Order.** Effects, then the overlay, then drawings. Arrows, text and counters therefore stay bright over the dimmed area.
  - **Source.** The overlay is drawn from the displayed spotlights: the document's, with `transient` in place of its document copy while one is moved or resized, or added when it is new (as `displayedEffects` does for effects). A transient spotlight is never appended to the drawings (`CanvasView.displayedDrawings`). A drag, move or resize therefore dims live. `EditorFlattener` has no transient and uses `document.spotlights`. With none displayed, nothing is drawn and `spotlightDim` is ignored.
  - **Overlay.** Black at `spotlightDim` alpha over the whole image, with each spotlight's shape cleared from it (rect, or ellipse in the rect), so overlapping spotlights form one union. It darkens only what the capture covers (Alpha, below).
  - **Routine.** `AnnotationDrawing.drawSpotlightOverlay(_:dim:in:imageRect:coverage:)` takes the shapes, the dim, the context, the image rect and an optional coverage list (`[(rect: CGRect, image: CGImage)]?`). It works in top-left image pixels, whatever CTM the caller set up for them, and saves and restores its own state.
  - **Method.** Under the caller's clip, set the composite blend mode, begin a transparency layer, fill the image rect with `.normal`, set `.clear` and fill each shape, end the layer. A blend mode set before the layer begins applies when the layer is composited; the fills inside use their own. A layer is as big as the clip, so every caller sets one (Canvas and Flattener, below).
  - **Alpha.** The overlay dims the picture, not its transparency. A transparent pixel stays transparent, so a window capture keeps its rounded corners and, with Include window shadow, its shadow margin keeps its alpha. A partly transparent pixel keeps its alpha and darkens; an opaque one gets black at the dim. 7c's shadow follows the content's alpha, so it keeps its shape. This amends 2.6 Export: pixels outside the effects, the drawings and the overlay equal the base byte for byte, and alpha survives everywhere, under the overlay too.
    - `coverage` nil (the flattener): the layer composites with `.sourceAtop`, which keeps the destination's alpha exactly and on an opaque pixel equals `.normal`. Probed at a 0.5 dim: alpha 0 stays `[0,0,0,0]`, and alpha 128 stays 128 with its colour halved.
    - `coverage` set (the canvas): the layer composites with `.normal`, because the canvas holds none of the base's pixels and `.sourceAtop` would draw nothing. When the list is not empty, after the holes are cleared, the routine sets `.destinationIn`, opens a nested layer, draws the list through `HighlighterBackdrop.draw` (the base tiles, then the shown effect tiles) and ends it. The overlay's alpha is then multiplied by the capture's: 0 over a transparent corner, unchanged over opaque pixels, and full over a redaction on a corner, as in the export. The canvas passes an empty list, which skips the nested layer, when the base has no alpha channel (`alphaInfo` `.none`, `.noneSkipFirst` or `.noneSkipLast`).
    - Partly transparent pixels (a window shadow) come out a little darker on the canvas than in the export: probed, alpha 128 shows as 160 at a 0.5 dim. Fully transparent and fully opaque pixels match.
  - **Canvas.** `CanvasView.draw(_:)` draws the overlay inside the image-pixel CTM block (2.6 Rendering, steps 1 to 3), not in view coordinates, and inside the background's rounded content clip when one is shown, so a background and an applied crop cut it as the export does. The order inside the block is highlighter backdrops, placeholders, overlay, drawings. It is not drawn after the final `restoreGState()`, which would dim the arrows, text and counters and escape the rounded clip. `imageRect` is the whole capture in image pixels; the view's dirty-rect clip bounds the layer, so a full repaint allocates one viewport-sized layer and a partial one less.
    - The canvas layer is not opaque and `draw(_:)` paints only the dirty rect, so the overlay is drawn on every `draw(_:)` while any spotlight is displayed and is not culled by the drawings' bounds test: a dirty rect that misses every hole still needs its dim. Only holes that miss the dirty rect may be skipped.
  - **Flattener.** `EditorFlattener` calls the routine in step 3, after `setBlendMode(.normal)` and the top-left flip and before the drawings loop. It is not called straight after the tile loop, where the blend mode is `.copy` and the CTM is still bottom-left. It calls it once per `ImageTiling.tiles(width:height:)` rect (save, `clip(to:)` the tile, draw, restore), never once for the whole image. Whole, a 3094 x 65,536 capture would allocate a layer of about 811 MB on top of the bitmap, the spike the strip copy of the base avoids; in strips the extra is one strip (about 200 MB), within the "flattened bitmap plus one strip" peak of 2.8. The tiles are integral, so the strips meet without a seam.
  - **Highlighter.** `HighlighterBackdrop` does not change: it still copies only the base and the shown tiles into the stroke's clip. The overlay is drawn after `drawHighlighterBackdrops` in the same pass, so it dims the backdrop copy once, as the flattener dims its bitmap, and the highlighter's multiply lands on dimmed pixels in both. The overlay is never drawn into the backdrop as well, which would dim the area under a stroke twice ((1 - dim)² on the canvas against (1 - dim) in the export) and leave a fringe on the stroke's edge pixels. It is never drawn before the backdrops either, whose opaque copy would hide it.
  - **Repaint.** When only `transient` changed, `refresh()` repaints the transient's old and new rects plus 8 pt. That is too little in two cases, so `CanvasView.Shown` gains two fields, set in both places that build it (`init` and `refresh()`). Both also join the equality list that guards the partial repaint (`now.document == previous.document && …`); adding them to `Shown` alone is not enough.
    - `hasSpotlights`: any spotlight displayed, the transient included. A change repaints the whole view, as a crop draft does: the first spotlight's drag begins, Escape cancels it, or its rect falls below the minimum size or grows back. While it stays true the old and new rects are enough, because a hole's move or resize changes the overlay only inside them.
    - `showsSpotlightOutlines`: `model.tool == .spotlight`. A change repaints the whole view, since a tool change alone changes nothing else `Shown` holds. Without it, pressing S, or leaving Spotlight, with nothing selected repaints nothing and the outlines are missing or stale.
- **Crop.** The overlay covers the whole image before the crop, as effects do; the crop is applied last. With a background, the overlay belongs to the content: export dims, then crops, then composes, so the fill, the padding and the rounded-off corners are never dimmed, and the canvas clips the overlay to the rounded content rect to match.
- **Editing.**
  - **Select.** A spotlight shows nothing inside its hole, so it hides nothing there. Its body is filled, as an effect's is: its shape grown by the tolerance, the rect or the inscribed ellipse, with no band and no line width. It has the 8 box handles and resizes through `resizedRect`, as a rectangle does. It ranks last. This amends the Select row in 2.6: `HitTester.topmost` tests every handle, then every body, each pass over the drawings front to back, then the effects front to back, then the spotlights front to back.
    - An arrow, text, counter or blur inside a spotlight is picked by a click whichever was made first. A text inside one is still re-edited by the Text tool's click and by Select's double-click, which both use `topmost`.
    - A click on bare image inside a spotlight picks it, so there a click does not deselect (Escape does). The dim corners of an ellipse's bounding box do not pick it.
  - **Order elsewhere.** `EditorModel.selectAll` follows the hit order: the frontmost drawing, else effect, else spotlight. `CanvasAccessibility.items` follows the paint order: effects, spotlights, drawings. This overrides 2.6's "every effect, then every drawing".
  - It moves, resizes with 8 handles, duplicates (⌘D and ⌥-drag), copies and pastes like a rectangle.
  - Delete removes it. Undo works per commit.

There is no colour (Shared, Selection chrome and colour). Shape and Dim are in the Options popover (Shared, Options).

#### Counter

- **Tool.** `EditorTool.counter`: letter `N`, title `Counter`, symbol `1.circle`, tool tip `Counter (N)`. It sits after Text and before Crop. `makeTool(for:)` gives it a new `CounterTool`.
- **Model.** `Annotation.counter(CounterMark)`, where `CounterMark { id: UUID; center: CGPoint; number: Int; diameter: CGFloat; color: RGBA }`. The centre and diameter are in image pixels. The kind name is `Counter`.
- **Placing.**
  - On mouseDown, `CounterTool` puts a new counter in `transient` from `makeAnnotation(.counter, from: press, to: press)`. The model gives it the next number, a diameter of `counterDiameterPoints × scale` and `strokeColor`. It centres it on the press, clamped so the whole circle is inside the image (or the applied crop); on an axis where the image or crop is smaller than the counter, it is centred on that axis.
  - Dragging moves nothing. On mouseUp, if `transient` still holds the counter, the tool commits it through `commitNewShape` as one step, `Add Counter`, at the press however far the pointer moved. Escape during the press clears `transient`, and nothing is placed.
  - A press outside an applied crop places nothing, as for Text (`CropGeometry.press` returns `.ignore`).
  - Only placing clamps. Moving, nudging, resizing, duplicating and pasting can leave part of a counter under the crop cover, as with other drawings.
  - **Number.** The next number is `max(numbers of every counter in the document) + 1`, or 1 when there is none. Deleting a counter does not renumber the others, and undo restores the number it had.
  - **Duplicate and paste.** Every new counter is numbered in `commitNewShape` (the `CanvasEditing` extension in ToolFactory.swift) through one pure helper, `Annotation.renumbered(in: AnnotationDocument)`. A counter comes back with the document's next number, whatever number it arrived with; any other kind comes back unchanged. Add, ⌘D, the ⌥-drag copy in Select (`Duplicate Counter`) and ⌘V all pass through it, so a number is never repeated, and undo restores the numbers the document had. `withID` still keeps the number.
    - During an ⌥-drag, `SelectTool` applies the helper to the copy it puts in `transient`, so the copy already shows the number it will commit with. Releasing Option mid-drag shows the moved original with its own number. The original is never renumbered.
  - **Paste cascade.** `AnnotationClip.placed` compares counters with their numbers ignored: centre, diameter and colour must match. This amends 2.6's "identical to it apart from its id" to "apart from its id (and, for a counter, its number)". A pasted counter therefore steps clear of every counter already at its place, and repeated pastes of one counter land 1, 2 and 3 steps away instead of stacking or landing on the original. `scaled(by:)` scales a counter's centre and diameter and leaves its number alone.
- **Look.**
  - A filled circle in the counter's colour whose outer 1.5 pt × `scale` (the capture scale passed to `AnnotationDrawing.draw`) is a white ring, stroked inset by half its width. Nothing paints outside `diameter`, so `AnnotationGeometry.bounds` is the circle's box plus the anti-alias margin, and the clamp keeps the ring inside the image or crop.
  - The number is drawn with `TextLayout.font(size:)` and `CTLineDraw`, with the text-matrix flip `drawText` uses (no AppKit, so the flattener can draw it), centred on the circle.
  - Its size is `min(0.55 × diameter, the size at which the line's typographic width is 0.8 × diameter)` (pure, `CounterLayout.fontSize(number:diameter:)`), so any number of digits fits. By estimate, three digits are the first to shrink.
  - The number is white when the fill's luma is under 0.5, otherwise black (`EditorPalette.contrastingTextColor(for:)`, pure). Luma is 0.2126 R + 0.7152 G + 0.0722 B on the sRGB components as stored (0 to 1), not linearised, the measure `Luminance` uses. WCAG relative luminance is not used: with a 0.5 cut-off it gives white digits on Orange, Green and Teal at about 2.2:1 to 2.6:1.
- **Colour.** The palette's active colour, as for Rectangle. With a counter selected, a colour change applies to it (`Color`).
- **Editing.** Select picks a counter inside its circle (grown by the tolerance). It moves, but has no resize handles; size comes from the option. A selected counter shows the dashed selection outline around its circle's bounding square and no handles, as text does. Delete, duplicate, copy and paste work as for other drawings. The number cannot be edited in 4c.

#### Shared

- **Toolbar.** Fourteen tools. `toolbarWithEveryToolFitsASmallDisplay` pins 14 tools and 1134 pt (1062 + 2 × 36 pt `ToolbarMetrics.segment`), within the 1152 pt that 90 % of a 1280 pt display allows. The `ToolbarMetrics.segment` comment ("twelve after 4b") is updated. The real minimum uses the measured `ToolSegmentedControl` fitting width, not this formula, so a hand check confirms it; if it does not fit, the plan raises it before shipping.
- **Keys.** `KeyRouting` maps `S` and `N`. Neither clashes: Save is ⌘S, and N has no editor chord.
- **Options.** `ToolOptionsView` stays one form. It gains three segmented rows after Pixel block. Rows that do not apply are disabled, as the Blur and Pixel sliders are, and are not swapped per tool. The enable rules are `EditorModel` predicates (like `editsHighlighter`), so tests reach them.
  - `Shape` (`Rectangle`, `Ellipse`) is enabled while Spotlight is the tool or a spotlight is selected. It always sets `spotlightEllipse`. With a spotlight selected it also changes that spotlight, as one step, `Spotlight Shape`; with none selected it adds no step.
  - `Dim` (`30 %`, `50 %`, `70 %`) is enabled only while the document has a spotlight and either Spotlight is the tool or a spotlight is selected. Otherwise it is disabled; it shows the document's dim, which is 50 % before the first spotlight. `EditorModel.applySpotlightDim(_:)` does nothing when the document has no spotlight, so a dim nothing shows adds no undo step and no unsaved change. A change is one step, `Spotlight Dim`, coalesced under one key, so a run of clicks is one step. Picking the value in effect commits nothing. Dim belongs to the document (one overlay), so it is not an editor default.
  - `Size` (`Small` 24 pt, `Medium` 32 pt, `Large` 44 pt, times the capture scale at creation) is enabled while Counter is the tool or a counter is selected. It always sets `counterDiameterPoints`. With a counter selected it also resizes that counter about its centre, as one step, `Counter Size`.
  - `Line width` keeps its rule: always enabled. With a spotlight or counter selected it sets only the default, since `withLineWidth` returns both unchanged.
  - The Options toolbar tool tip becomes `Tool options` (it read `Line width, blur radius and pixel block`), and the `ToolOptionsView` doc comment follows.
- **Defaults.** `EditorDefaults` gains `spotlightEllipse: Bool` and `counterDiameterPoints: CGFloat` (standard: false, 32). `EditorModel` holds them under the same names, set in `init`. `currentDefaults`, `storeChangedDefaults`, `AppSettings.editorDefaults`, its registered defaults and its init read all carry them, under the keys `editorSpotlightEllipse` and `editorCounterDiameterPoints`. 32 is registered, since `double(forKey:)` reads 0 for a missing key, and a stored size other than 24, 32 or 44 reads as 32. The "five editor keys" comments become seven.
- **Wiring the compiler flags.** `EditorModel.makeAnnotation` builds `.spotlight` and `.counter`, and `FakeCanvasEditing` in CanvasToolTests mirrors it. `CropGeometry.press` returns `.clampedToEdge` for Spotlight and `.ignore` for Counter. `scaled(by:)` scales a spotlight's rect and a counter's centre and diameter. `withColor` recolours a counter and returns a spotlight unchanged. `HitTester.handles(for:)` gives a spotlight the 8 box handles and a counter none. `AnnotationGeometry.bounds` is a spotlight's rect and a counter's circle box.
- **Selection chrome and colour (sites the compiler will not flag).** Two lookups end in `default` or a `??` chain, so a new `Annotation` case compiles without them. 4c makes both exhaustive, so the next kind is flagged. The Colour item also gets a rule.
  - `AnnotationDrawing.drawSelection` takes its outline rect from a new `AnnotationGeometry.selectionOutline(of:) -> CGRect?`. It is an exhaustive switch and replaces `effectRect ?? strokeOutline ?? textFrame`. A selected counter gets the dashed outline (white under black dashes, as for text) around the bounding square of its circle, and no handles. A selected spotlight gets the same outline around its rect, plus its 8 handles. This selection outline is separate from the Spotlight tool's outlines.
  - `EditorModel.color(of:)` loses its `default` and returns a counter's colour (nil for a spotlight). So `activeColor`, the toolbar swatch and the palette's current-swatch ring show the selected counter's colour.
  - `validateToolbarItem` returns `EditorModel.colorApplies` for `.color` (it returns true for every item but Copy, Save and Upload today). `colorApplies`, a computed property, is false while the tool is Spotlight and the selection has no colour, and while a spotlight is selected, so the palette never quietly changes `strokeColor` with nothing to show for it. This is a new rule; nothing disables the Colour item for Crop.
- **Undo names.**
  - Tools: `Add Spotlight`, `Move Spotlight`, `Resize Spotlight`, `Duplicate Spotlight`, `Paste Spotlight`; `Add Counter`, `Move Counter`, `Duplicate Counter`, `Paste Counter`.
  - Model: `Spotlight Shape`, `Spotlight Dim` and `Counter Size`, new `EditorModel.ActionName` entries in the style of `Line Width` and `Text Size`. The existing `Color` (a counter's colour), `Move` (arrow-key nudges) and `Delete` cover the rest.
- **Accessibility.** Spotlights are labelled `Spotlight 1`, `Spotlight 2`, …, numbered per kind as today. A counter is labelled `Counter <its number>` and has no value, so after a deletion what VoiceOver reads matches the picture. The order is effects, spotlights, drawings (Editing, above).
- **Object clipboard.** The annotation clipboard (`AnnotationClip`) carries both new kinds. A document from before 4c decodes unchanged.

**Tests (Swift Testing).**
- `EditorToolTests`:
  - fourteen tools in the stated order;
  - letters unique, with `S` and `N` mapped;
  - Spotlight is not an effect;
  - `toolbarOrderCoversEveryToolOnce` updated: its `dropFirst(6).prefix(2) == [.ellipse, .line]` gets `[.arrow, .ellipse]` once Spotlight sits before Rectangle, so it checks that Ellipse and Line follow Arrow.
- `SpotlightRenderingTests` (through `EditorFlattener` on a test image unless stated):
  - a pixel outside every spotlight is darkened by the dim;
  - a pixel inside a rectangle and inside an ellipse is unchanged;
  - an ellipse's bounding-box corner is dimmed;
  - two overlapping spotlights leave their union undimmed;
  - an arrow drawn over the dim keeps its colour;
  - no spotlight means nothing is dimmed;
  - the 30 / 50 / 70 % dims give the expected darkening;
  - the crop is applied after the overlay;
  - a fully transparent pixel outside every spotlight stays `[0,0,0,0]`;
  - an alpha-128 pixel keeps alpha 128 and its colour is darkened;
  - an opaque base gives the same pixels as a `.normal` composite;
  - a solid redaction over a transparent corner is opaque and dimmed;
  - a capture taller than `ImageTiling.maxTileSide` is dimmed the same on both sides of a strip seam, with a spotlight straddling the seam;
  - in the canvas's order, into a bitmap (`HighlighterBackdrop.draw` inside a saved state clipped to the stroke, then `drawSpotlightOverlay` with a coverage list, then the highlighter through `AnnotationDrawing.draw`), the pixel under a highlighter in the dimmed area equals the flattener's within one level per channel, and in a hole it is the undimmed multiply;
  - `drawSpotlightOverlay` with a coverage list, run into an empty bitmap as in `HighlighterBackdropTests`, leaves a transparent pixel of the capture at alpha 0.
- `CounterTests`:
  - next number with none, after 1-2-3, and after deleting 2 (gives 4);
  - ⌘D, the ⌥-drag copy and ⌘V each number the new counter max + 1, so no number repeats;
  - three pastes of one counter (modelled on `EditorModelTests.pasteOntoItsOriginalCascades`) land at +20, +40 and +60 px at scale 2, as counters 2, 3 and 4;
  - clamping inside the image and the crop, and centring on an axis where the image or crop is smaller than the counter;
  - the text colour for every swatch: white on Black, Red, Blue, Purple and Pink; black on Orange, Yellow, Green, Teal and White; and black for a light-grey custom colour (180/255 grey), which the linearised measure would give white text;
  - a rendered counter's pixel at (centre.x, centre.y + 0.35 × diameter), below the glyph and inside the ring, is the fill, and a pixel just inside the edge is white;
  - numbers 9, 42 and 100 each fit in 0.8 × diameter, and 100 is drawn smaller than 0.55 × diameter.
- `AnnotationDocumentTests`: bounds and move for both kinds; a Codable round trip; a document without `spotlightDim` decodes and reads 0.5; `spotlights` holds the spotlights in creation order and `drawings` leaves them out; both kinds survive `scaled(by:)` (a counter's centre and diameter scale, its number does not).
- `HitTesterTests`:
  - a spotlight's body, its 8 handles and its resize; a counter's body inside its circle, and no handles;
  - an arrow inside a spotlight is hit first, whether it was made before or after the spotlight;
  - a click on bare image inside a rectangle spotlight hits its `.body`, and so does one within the tolerance outside its edge;
  - inside an ellipse spotlight a click hits it, and on its bounding-box corner it misses;
  - a redact inside a spotlight is hit by a click on it, whichever was made first;
  - a spotlight's handle within the tolerance beats an effect's body under it.
- `CanvasToolTests` (both kinds added to `FakeCanvasEditing.makeAnnotation`):
  - the Spotlight drag commits `Add Spotlight`; Shift squares it; a tiny drag adds nothing;
  - a Counter click and a Counter drag both place at the press, as one `Add Counter`; Escape during the press places nothing;
  - with counters 1 and 2, an ⌥-drag of counter 1 shows a transient copy numbered 3, commits `Duplicate Counter` with number 3 and leaves counter 1 untouched; releasing Option mid-drag shows the moved original numbered 1;
  - a text inside a spotlight made after it is re-edited by the Text tool's click and by Select's double-click.
- `EditorModelTests`:
  - ⌘A with an arrow made before a spotlight selects the arrow, and with only a spotlight selects the spotlight;
  - Shape, Dim and Size on a selected spotlight or counter are each one step under their names, and undo and redo restore them; Size resizes about the centre;
  - Shape and Size with nothing selected change only the default and add no step;
  - Dim with no spotlight adds no step and leaves `hasUnsavedChanges` false, and picking the dim in effect adds no step;
  - Shape, Dim and Size are enabled only under the rules above, and `colorApplies` is false for Spotlight with no coloured selection and with a spotlight selected;
  - a new counter has `counterDiameterPoints × scale` and `strokeColor`;
  - with a counter selected, `activeColor` is its colour and `applyColor` recolours it as `Color`; with a spotlight selected, `activeColor` is unchanged.
- `AnnotationClipTests`: a counter and a spotlight round-trip; a counter placed from a 2x clip into a 1x editor keeps its point size (centre and diameter halved, number kept until the model renumbers it); `placed` treats a counter with a different number at the same place as identical, so it steps, and one with a different diameter or colour as different.
- `SelectionOutlineTests` (or in `ArrowGeometryTests`): `selectionOutline` of a counter is its bounding square and of a spotlight its rect; the existing kinds are unchanged.
- `EditorBackgroundExportTests`: with a background, a transparent corner outside every spotlight shows the undimmed fill.
- `KeyRoutingTests`: `S` and `N`.
- `EditorWindowGeometryTests`: 14 tools and 1134 pt.
- `CanvasAccessibilityTests`: the order is effects, spotlights, drawings; spotlights are numbered per kind in that order; a counter is labelled by its own number with no value, also after a middle counter is deleted.
- `AppSettingsTests`: the two editor defaults, 32 registered, and a stored size outside 24/32/44 reading as 32.
- Only if the plan extracts them as pure helpers: `displayedSpotlights(in:transient:)` (like `RedactionTileCache.orderedEffects`) puts the transient in place of its document copy and appends a new one; the full-repaint decision is true when `hasSpotlights` or `showsSpotlightOutlines` flips and false for a transient-only change. Otherwise the hand checks cover them.

**Hand checks** (in `docs/testing/phase-4c-manual-checklist.md`; no unit test reaches `CanvasView.draw`'s order or repaints):
- On a capture with no spotlight, drag the first one: the whole image dims live and the hole follows the pointer. Press Escape mid-drag: the dim goes entirely. Shrink the drag below the minimum: the dim goes. Move and resize a rectangle and an ellipse spotlight with Select: the hole follows.
- With spotlights in the document and nothing selected, press S: every dashed outline appears at once. Press V, or pick another tool from the toolbar or with R, A or T: they go at once. Check the outlines at 50 %, 100 % and 400 %.
- Draw a highlighter stroke across the dim edge: the canvas shows the same darkness under the stroke as the saved or copied image. An arrow over the dim stays bright in both.
- With a crop and a Background on, the dim stops at the rounded content rect; the padding and rounded corners are not dimmed, and match the export.
- Spotlight a window capture with Include window shadow on and off: the export's corners and shadow margin stay transparent, and the canvas shows no dark corners.
- A selected spotlight shows its dashed outline and eight handles. Placing a counter leaves it showing the dashed outline and no handles; clicking another counter with Select moves the outline; clicking empty space clears it.
- The Colour item is disabled for Spotlight and with a spotlight selected. The Options rows enable per tool and selection, and Dim is disabled before the first spotlight.
- The 14-tool toolbar shows every item, with no chevron, on a 1280 pt display with a long title.
- Counters at Small on a 1x capture are legible and their ring shows.
- ⌘C a counter in one editor and ⌘V it twice in another at a different scale: new numbers, a cascade, the same point size.
- VoiceOver reads spotlights and counters in painting order, and reads `Counter 3` for the third counter after the second is deleted.

**Phase 4c (built).** Delivered 2026-10-23 on `editor-4c`. The suite reads `Test run with 1269 tests in 130 suites passed` (1193 tests in 126 suites before 4c); the hand checks are in `docs/testing/phase-4c-manual-checklist.md`. No entitlement and no package were added, and the only new settings keys are the two editor defaults. The build follows the text above, with these points:
- Model: `SpotlightShape` and `CounterMark` sit beside `ShapeBox` in Annotation.swift. `Annotation` gains the accessors `spotlightShape`, `counterMark` and `isSpotlight`, and the helpers `withSpotlightShape(isEllipse:)`, `withCounterDiameter(_:)` and `renumbered(in:)`. `AnnotationDocument` gains `spotlightDim`, `defaultSpotlightDim` (0.5), `effectiveSpotlightDim`, `withSpotlightDim(_:)` (which stores 0.5 as nil), `spotlights` and `nextCounterNumber`. `EditorPalette` gains `spotlightDims` (0.3, 0.5, 0.7), `counterDiametersPoints` (24, 32, 44), `defaultCounterDiameterPoints` and `contrastingTextColor(for:)`.
- New pure helpers and files: `SpotlightGeometry.displayedSpotlights(in:transient:)` (SpotlightGeometry.swift) puts a spotlight transient in place of its document copy, or last when it is new, and ignores a transient of any other kind. `CounterLayout` (CounterLayout.swift) has `center(forPress:diameter:within:)`, `fontSize(number:diameter:)` and the constants `fontSizeFraction` (0.55) and `widthFraction` (0.8). `CounterTool` is in CounterTool.swift. `AnnotationGeometry.selectionOutline(of:) -> CGRect?` is an exhaustive switch and replaces the old chain in `drawSelection`; `strokeOutline(of:)` stays, no production code calls it now, and the tests still do.
- `CounterLayout.fontSize` is iterative. It starts at 0.55 × the diameter and, while the line's typographic width is over 0.8 × the diameter, scales the size by `limit / width` and measures again, at most ten times. The system font's width does not scale exactly with its size, so one pass is not always enough; measured on the real font at diameters 24 to 132 with numbers 1 to 12345 it settles in one to seven passes (888 at 48 px was the slowest). The cap bounds a line that keeps landing a hair over, so a line could at worst end a fraction of a pixel wider than 0.8 × the diameter. Every case the tests pin fits exactly. The number is centred across by `CTLineGetTypographicBounds` and down by the font's cap height (the baseline is at `center.y + capHeight / 2`). `AnnotationDrawing.counterRingPoints` (1.5) names the ring's width, and the ring is stroked on the circle inset by half of it.
- Numbering: `commitNewShape` applies `renumbered(in:)` before it commits, so the id, and so the selection, is unchanged. `SelectTool` applies it to its ⌥-drag copy and never to the original. `AnnotationClip.placed` compares through a private `isIdentical(_:to:)`: two counters match on centre, diameter and colour, anything else on `withID(id) ==` as before. `CounterTool.mouseDown` clears `transient` before `makeAnnotation`, so a stale transient's id is never reused.
- The overlay: `drawSpotlightOverlay(_:dim:in:imageRect:coverage:)` follows the method above and sets no clip of its own. The flattener calls it once per `ImageTiling.tiles` strip, with `coverage: nil` (`.sourceAtop`). The canvas passes `backdropLayers` (the base tiles, then each displayed effect's shown tile) or `[]` when the base has no alpha. Both the highlighter backdrops and the overlay use that list, which is now built once per draw rather than once per stroke, and the backdrop interpolation quality is set around the overlay. A pending redaction's placeholder is not in the list, so while its tile renders over a transparent corner the canvas shows the placeholder undimmed there; it is dimmed once the tile arrives.
- The tool's outline: `AnnotationDrawing.drawSpotlightOutline(_:transform:scale:in:)` draws it in view space after the crop cover. It follows the shape, so an ellipse spotlight gets an ellipse and not its bounding box. It is snapped to device pixels and inset 0.5, as the selection outline is, and both go through a shared private `strokeTwoTone`. `drawSelection` also skips a null outline (a rect under 1 pt), where before it stroked `.null`.
- Repaint: `CanvasView.Shown` is internal and gains `hasSpotlights` and `showsSpotlightOutlines`. `allowsPartialRepaint(since:)` is the guard, with the six old fields and the two new ones, and `init` and `refresh()` build `Shown` through one `static func shown(of:)`. `baseHasAlpha` is decided once in `init`. No test reaches the on-screen repaint: a probe could not tell a missed partial repaint from AppKit's own invalidation on a tool change, so stale outlines or a stale dim after S, V or Escape rest on `SpotlightDisplayTests` and the hand checks.
- Order: `HitTester.topmost` reverses `spotlights + effects + drawings`; `EditorModel.selectAll` falls back to `document.spotlights.last(where:)`; `CanvasAccessibility.items` lists `effects + spotlights + drawings`, and a counter's label is `Counter <its number>` without advancing the per-kind count, so `Arrow 1` is unaffected by counters.
- Options and model: `EditorModel` gains `ActionName.spotlightShape`, `.spotlightDim` and `.counterSize`; the predicates `spotlightShapeApplies`, `spotlightDimApplies`, `counterSizeApplies` and `colorApplies`; `activeSpotlightEllipse` and `activeCounterDiameterPoints`; and `applySpotlightShape(isEllipse:)`, `applySpotlightDim(_:)` and `applyCounterSize(points:)`. Shape and Size are keyed per annotation (`Spotlight Shape-<id>`, `Counter Size-<id>`) and Dim under the one key. `color(of:)` has no `default`. The three rows come after Pixel block in `ToolOptionsView`, with a `counterSizeLabels` array (`Small`, `Medium`, `Large`) zipped with the palette's stops. The Options tool tip is `Tool options`.
- Shape and Size act on a selection, and a spotlight or counter is selected as soon as it is drawn. Picking Shape right after drawing a spotlight, or Size right after placing a counter, therefore changes that one as well as the default. That is the rule above; the checklist asks Tim whether it surprises him. The same holds for colour: recolouring a selected counter also sets `strokeColor`, so the next counters take it, as for Rectangle.
- Defaults: `AppSettings` has the keys `editorSpotlightEllipse` (false) and `editorCounterDiameterPoints` (32, registered); a stored size other than 24, 32 or 44 reads as 32. `currentDefaults` and `storeChangedDefaults` carry both.
- Toolbar width: `toolbarWithEveryToolFitsASmallDisplay` pins 14 tools and 1134 pt. Its sibling `measuredToolbarFitsASmallDisplay` (EditorToolbarTests) changed in review. As first written it measured a fresh `makeToolsControl` (392 pt) while `minimumToolbarContentWidth()` reads the installed control first (493 pt), so it computed about 1033 pt against a real 1134 pt and a 15th tool would still have passed. It now builds a real `EditorWindowController`, asserts the `.tools` item's view is a `ToolSegmentedControl`, ties `contentMinSize.width` to `minimumToolbarContentWidth()` and checks that against 90 % of 1280 pt (1152 pt); a mutation test with a 15th segment (1169 pt) fails it. A probe in the Debug test host (not a screen) measured the minimum as 1134 pt, equal to the formula, with every one of the ten toolbar items visible down to 1096 pt and Save and Upload in the overflow menu at 1095 pt. That leaves 18 pt under the 1152 pt bound, so a 15th tool would need the bound revisited. The hand check on a 1280 pt display is still open.
- Beyond the plan: `EditorToolbarTests.currentDefaultsCarryEveryEditorDefault` (an editor opened with custom defaults reports them through `currentDefaults` and follows changes), `FakeCanvasEditing.makeAnnotation` builds `.counter` with a 64 px diameter, and `EditorBackgroundExportTests.makeModel` takes `clearCorner:`.
- Not done on a screen: nobody has looked at the editor with a real pointer. Each task ran a throwaway probe in the Debug test host (the app process, a real `EditorWindowController` and `CanvasView`, synthesized events, pixels read from the canvas and the export, renders looked at) in place of the GUI hand checks, because computer-use had no app grant. The probes covered the live dim, Escape and the minimum size; the outlines at 50 %, 100 % and 400 %; the highlighter across the dim edge; a crop with a Background; a window capture with and without the shadow; the selection chrome; the Options rows; placing, selecting, recolouring and resizing counters; counters at a crop's edge; ⌘C at 2x and ⌘V into a 1x editor; and the VoiceOver labels through `accessibilityChildren`. They did not cover the partial repaints, moving and resizing both shapes with Select, the 1280 pt display, VoiceOver itself or the feel of a real pointer.
- The Options popover is a `Grid` 340 pt wide, with one-line labels in a right-aligned column (fixed 2026-10-23 after Tim saw `Line width` wrap one letter per line once a spotlight was drawn; the old 300 pt `Form` in `.columns` style squeezed the label column). `ToolOptionsViewTests` checks the width against the widest row. Seen and left alone: a White counter has no edge on a white capture, since its ring is white on a white fill and the ring's colour is fixed above. Partly transparent pixels, such as a window shadow, show a little darker on the canvas than in the export, as noted under Alpha.
- Whole-branch review: documentation only, no code. In the checklist, releasing Option mid-drag is its own item (inside the numbered ⌥-drag run it turned the copy into a Move and the paste read 4, not 5), the Dim run ends on a new value so ⌘Z shows a change, the run up to `100` places counters with clicks (a held ⌘D walks its copies off the image), and the strip-seam check finds the seam in the capture with `sips` and compares each pixel with the original instead of assuming the capture started at the page's top. `px.swift` lets Core Graphics own its buffer, refuses a point outside the image and says it prints sRGB-converted values. The 2.1 After-capture row, 2.6's scope line and section 6 now say 4c built Spotlight and Counter only.
- Tests as listed above, plus `SelectionOutlineTests`, `SpotlightRenderingTests`, `SpotlightDisplayTests` and `CounterTests` as new suites. In `toolbarOrderCoversEveryToolOnce`, `dropFirst(phase4a.count).prefix(2)` reads `[.arrow, .ellipse]`.

Observations from the checklist run are still to be written down here by Tim: whether the 14-tool toolbar fits at 1280 pt with a long title and the narrowest width the window allowed, whether a stale outline or a stale dim ever appeared after S, V, Escape or a tool change, whether the canvas matched the saved file under a highlighter and at a window shadow's edge, how the counters' ring and digits compared with the saved file, whether Shape or Size changing the selected annotation right after it was drawn surprised him, and how long Save As… took on the tall capture with a spotlight. None of the GUI checks had been run when this was written.

### 2.13 Small changes (2026-10-23)

Two changes Tim asked for after testing recording R1. They are on the branch `small-tweaks`, stacked on `coordinator-split`.

**Ask before deleting.**
- **Setting.** General gets `Ask before deleting`, on by default, stored as `AppSettings.confirmBeforeDeleting` (key `confirmBeforeDeleting`, default true). It sits after `Play sound`, with the caption `Delete removes the file, the upload and the Recent Captures entry. When this is off, Delete acts at once.`
- **Off.** `deleteCapture(recordID:)` skips `confirmDelete(of:)`: the card's and row's Delete then act at once.
- **Unchanged.** The second alert (`confirmRemoveFromHistory`), which appears only after the storage `DELETE` failed or a save-folder file could not be removed, still appears. It asks what to do about something that could not be deleted, which a routine confirmation does not cover.
- **No other gate.** Nothing else reads the setting; retention pruning never asked and still does not.
- **Labels.** The card's menu item and the row's button read `Delete…` while Delete asks first and `Delete` when it acts at once (`CaptureDeletion.actionTitle(confirmBeforeDeleting:)`).

**Size in Recent Captures.**
- **Format.** Each row's detail reads `3 hours ago · 5 KB`: the relative time, a middle dot with a space either side, then the size. The upload state follows as now, `3 hours ago · 5 KB · Uploading`.
- **Formatting.** `ByteCountFormatter` with `countStyle = .file`, the same decimal units Finder shows. Zero and unknown sizes show no size part.
- **Where the size comes from.** `CaptureRecord.byteCount: Int?` (`decodeIfPresent`, nil for old records) holds the size of the object the record's link or file points at:
  - **On save:** the bytes written, for a screenshot (the PNG) and for a recording (the file after its move).
  - **Edits and replaces:** an editor Save, or a Trim, sets the new file's size. For a Trim (recording R2) it is the trimmed file's size, read before the put moves it, and `finishTrimWrite(id:duration:byteCount:)` sets it with the duration; a failed Save and Upload keeps the trimmed file's size, as a failed editor Upload keeps the edited file's. As built (H2), the size and the length are read from the trimmed file with `VideoValidation.inspect`; a size that cannot be read leaves none, for the next launch's backfill.
  - **On upload:** `.uploaded` sets the size of the bytes sent, which is Clop's result when Clop's result was accepted. The size shown is then the uploaded object's.
  - **Not changed:** a failed upload, or a delete of the local file alone.
  - **Also set (built):** a recording recovered at launch gets its file's size, and an editor Upload's local write sets the edited file's size until the upload succeeds. After a failed editor Upload, the record goes back to its earlier link and keeps the edited file's size.
- **Old records.** At launch, records with no `byteCount` and a local file get it from the file's `fileSizeKey` resource value. That is `pending/` directly, and the save folder under its scope, all in one pass off the main actor. The file is never read. Records with neither a size nor a local file show no size.
- **Pure parts.** `RecentCaptureFormatting.detail(for:now:locale:isOptimizing:)` takes the size from the record. The size text comes from `RecentCaptureFormatting.sizeText(_:)`, in the current locale: `ByteCountFormatter` has no locale property, and the format-style API that takes one writes `kB`. When a row is too narrow for the whole line, it drops the size before it drops the upload state.

**Tests (Swift Testing).**
- `RecentCaptureFormattingTests`:
  - time and size;
  - time, size and each upload state;
  - no size when nil or zero;
  - the middle-dot separator;
  - `sizeText` for 999 bytes, 5 KB, 1.2 MB and 3.4 GB (runs only when the Mac's locale is US English).
- `CaptureRecordTests`: `byteCount` round-trips, and old JSON decodes as nil.
- `AppSettingsTests`: `confirmBeforeDeleting` defaults to true and persists.
- `CaptureDeletionTests` or a pure helper: whether Delete asks, for each value of the setting. The alert itself is a hand check.
- A backfill helper test over a temporary folder: sizes are read from attributes; missing files are skipped.

Hand checks: turn the setting off and delete from a card, a row and a pin (no alert); make a remote delete fail with the setting off (the second alert still appears); check rows for a screenshot, a recording, an upload-only capture before and after upload, and a capture saved before this change.

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
- The overlay shows a progress ring during upload, then a checkmark and the URL. Clicking it copies the URL again. Dragging a card out drops a file: a copy of the capture kept in TidyShot's container, handed over as a file URL (2.9).
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
| Distribution | Developer ID signed and notarized, outside the App Store. Hardened runtime on, App Sandbox on (decided 2026-10-19) | Entitlements: `network.client`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, and (Phase 7, spec 2.7) `temporary-exception.mach-lookup.global-name` for `com.lowtechguys.Clop.optimisationService` and `com.lowtechguys.Clop-setapp.optimisationService`, which needs App Review approval if a Mac App Store build is ever made. Save folder chosen via `NSOpenPanel` and persisted as a security-scoped bookmark. Keeps the App Store open as a later channel |
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
- **Settings**: SwiftUI `Settings` scene. Tabs: General (hotkeys, after-capture action, save folder), Capture (cursor, shadow, freeze, timer, format), Upload (destinations list, test button, naming), Overlay (position, auto-close). There is no Advanced tab: URL commands are in General and history retention in Overlay (2.9).
- **AppCoordinator**: menu bar item, hotkey registration, and the single place that wires hotkey to overlay to engine to queue to UI. Also handles the URL scheme. One `@Observable final class` of `TidyShot/App/`, split across eleven files with no change in behaviour (`2026-10-23-coordinator-split-design.md`): the root keeps every stored property and the extensions hold the members, moved byte for byte. Recording R2 adds a twelfth file, `+Trim`, below.
  - `AppCoordinator.swift`: every stored property, grouped by area; `shared`, `init`, `start`, shortcut registration, the URL command and desktop-icon wiring, quit, and `loadContent` and `withCaptureLock`, which image capture and recording share.
  - `AppCoordinator+Capture.swift`: the image capture entry points (area, window, fullscreen, previous area, All-in-One, self-timer, scrolling, text), `capture(_:excludingWindows:duringSelection:)` and `revealLastCapture`.
  - `AppCoordinator+Recording.swift`: Record Screen and Record Fullscreen, stop, the hand-off, recovery of a leftover recording, and the recording save; `RecordingSaveMode`, `RecordingPhase` and `RecordingShortcutAction`.
  - `AppCoordinator+Save.swift`: the one save path (`save`, `finishSave`), the file and pending-file writes, the clipboard rule and the thumbnail.
  - `AppCoordinator+Overlay.swift`: showing, restoring and refreshing the Quick Access cards.
  - `AppCoordinator+Upload.swift`: the upload lanes, destinations and credentials, `startUpload`, Clop's step, retry, `cancelUpload` and the upload events.
  - `AppCoordinator+RecordActions.swift`: the actions on a record from a card, a pin or a Recent Captures row (copy, open, Save As, reveal, download); `CopyImageError`.
  - `AppCoordinator+Delete.swift`: the one delete path (`deleteCapture`, `removeRecord`) and the teardown that retention pruning shares.
  - `AppCoordinator+DragOut.swift`: the drag copies, their staging, prefetch and clean-up; `DragCleanupStep`.
  - `AppCoordinator+Editor.swift`: the editor bridge (2.6): open, present, save, Save As, upload, copy and close.
  - `AppCoordinator+Pins.swift`: Pin to screen and the retained capture.
  - `AppCoordinator+Trim.swift` (recording R2): Trim… for an MP4 recording, a second editor-like area. It holds `hasUploadDestination`, `trimMenuState(for:)`, `trimCapture` and its download, the pass, the put, `finishTrimWrite`, Save and Upload and `uploadTrimmed` (the R2 design's built notes, H2); `TrimWindowController` (`TidyShot/Trim/`) is the window. Its state, `trimWindows`, `openingTrimIDs`, `trimPasses` and `trimmingIDs`, is in the class body under `// MARK: Trim state`; `+Upload` and `+Delete` read the marker, and `+Delete` closes the window. It also calls `showCardPoster` (`+Overlay`) for the card's new poster. It reaches `replaceThumbnail` (`+Editor`) and `downloadSource` (`+RecordActions`), the two members R2 widened.
  - Conventions:
    - New stored state goes in the class body in `AppCoordinator.swift`, under its area's group, with a `//` line naming any other file that writes it.
    - New members start `private` in their area's file. Widening one is a reviewed decision, listed in the PR.
    - A new area gets a new `AppCoordinator+<Area>.swift`.
    - Outside `TidyShot/App/AppCoordinator*.swift`, code uses only the surface the split design lists in its 3.5 and new entry points made for it. A review that touches the coordinator greps outside the family for every member the split widened (the split design's section 6, and its plan's Task 7, have the command).
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
- Menu bar on `NSStatusItem` + `NSMenu`; Recent Captures hover submenu with custom rows (thumbnail, name, relative time, copy URL, copy image, delete) and a floating preview on the side of the submenu away from the status menu (the other side when there is no room, always on screen); gallery window removed.
- `S3Destination.download(key:)` (signed GET) for copy-image on upload-only captures.
- Two-button delete alert, with a "remove from history anyway" fallback only after a failed storage DELETE or a save-folder file that cannot be removed.
- `{app}` token removed with migration of stored templates.
- Upload tab: "Required" prompts with example captions; connection test result without the probe URL.
- Adaptive crosshair colour from the snapshot.

### Phase 4: annotation (1 to 2 weeks)
Design in 2.6. One release in two PRs.
- 4a: crosshair and loupe contrast; editor window with Select, Redact, Pixelate, Blur, Rectangle, Arrow, undo, colour palette, line widths and zoom; Save over (or Save As… with no file), Save As…, Copy, Upload (same key, closing the editor) and Upload as New; Annotate on the overlay and on Recent Captures rows.
- 4b: Ellipse, Line, Pencil, Highlighter, Text, Crop; duplicate, object copy and paste, Space-drag pan, canvas accessibility.
- 4c: Spotlight and Counter on `editor-4c`, built (design in 2.12); the editable project format and "open editor" as an after-capture action stay later.

Delivered 2026-10-20: 4a in PR 7 (merge commit 9193586) and 4b in PR 2 on `phase-4b-annotation`. Phase 4 is released when PR 2 merges. Design and what was built: 2.6. 4c was delivered 2026-10-23 on `editor-4c`; design and what was built: 2.12.

### Phase 5: scrolling capture (1 to 2 weeks)
Design in 2.8.
- Vertical scrolling capture of an area or window: manual mode first (the user scrolls, TidyShot captures and stitches), with a live preview, Done, Cancel and an automatic end.
- Then auto-scroll on the same engine, behind the post-event permission flow.
- Later: horizontal scrolling.

Delivered 2026-10-21: manual and auto-scroll on `phase-5-scrolling`. Phase 5 is released when its PR merges. Design and what was built: 2.8.

### Phase 6: overlay and capture polish (about 7 days, two PRs)
Design in 2.9.
- 6a: cursor and window-shadow options, freeze screen, a stack of Quick Access cards on the capture's display with close and restore, Save As… and Copy Image on the card, drag-out, Capture Previous Area.
- 6b: All-in-One mode, self-timer, pin to screen, and the URL scheme (`tidyshot://capture-area?action=upload` and friends) behind a setting for silent captures.

Delivered: 6a on 2026-10-21 on `phase-6-polish` (PR 13); 6b on 2026-10-21 on `phase-6b-polish`. Phase 6 is released when the 6b PR merges. Design and what was built: 2.9.

### Phase 7: extras (as wanted)
- Optimise images with Clop before upload (see 2.7): merged 2026-10-21 (PR 15).
- 7b: Capture Text (OCR via Vision, QR codes) and Hide desktop icons, on `phase-7b-text-icons`. Design in 2.10.
- 7c: Background tool and window-with-background, on `phase-7c-background`. Design and what was built: 2.11.

### Later: screen recording
Separate design document. Will reuse Uploader, Naming, History, and Overlay.

## 7. Decisions needed before Phase 1 and 2

1. **Minimum macOS**: decided, 26.0. Capture uses `SCScreenshotManager.captureScreenshot(rect:configuration:)` and `captureScreenshot(contentFilter:configuration:)` with `SCScreenshotConfiguration`.
2. **Clipboard in upload mode**: decided, URL only, with an "Also copy image" setting off by default.
3. **Object key default**: decided, random 6 characters from `[A-Za-z0-9]` plus extension, configurable length (4 to 32) and an optional prefix folder. Amended 2026-10-19: the key is a template defaulting to `{random:6}` (see 2.4), which keeps this default while allowing dates, hostname, and literal folders. Collision handling: issue a `HEAD` on the key before `PUT` and regenerate on 200.
4. **Public read**: decided, rely on a bucket policy or CDN. No ACL header by default; a per-destination "Send public-read ACL" toggle adds `x-amz-acl: public-read`. Test Connection performs a PUT, then an unauthenticated GET on the public URL, and reports if the object is not readable.
5. **Image format default**: decided, PNG always. A per-destination format override (JPEG, HEIC, quality) is a Phase 3 item.
6. **Sandbox**: decided, on. Save folder access via security-scoped bookmarks. Consequences: on the first capture the app asks for a save folder with `NSOpenPanel` and keeps it as a security-scoped bookmark; drag-out from the overlay hands over a file URL to a copy in the container, not a file promise (amended in Phase 6, see 2.9); the "hide desktop icons" feature must be implemented as a wallpaper-coloured cover window at desktop icon level rather than a Finder `defaults` write; the URL scheme and Carbon hotkeys work unchanged.
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
