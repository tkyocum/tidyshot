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
| After-capture action | Preference: show overlay, save, copy, open editor, or upload automatically | P0 | Upload-and-copy-URL is the default this app exists for. Phase 3 adds "Upload only" (no local file kept), see 2.4. "Open editor" is deferred to Phase 4c; Phase 4 opens the editor from the overlay and Recent Captures, see 2.6 |
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

**Recent Captures as a hover submenu.** The gallery window is replaced. The menu bar moves from SwiftUI `MenuBarExtra` to an AppKit `NSStatusItem` with an `NSMenu`, because the "Recent Captures" item must open on hover and hold rows with custom views. Its submenu lists the newest captures (up to 15), each row a custom view: thumbnail, name, relative time ("2 minutes ago"), and three small icon buttons: copy URL, copy image, delete. Clicking the row copies the URL (or the file when never uploaded) and closes the menu. Hovering the thumbnail shows a larger image (up to 560 by 420 points) in a floating preview panel placed on the side of the submenu away from the status menu, falling back to the other side when there is no room and always kept on screen; it follows the hovered row and hides when the menu closes. Copy image puts the PNG and TIFF on the clipboard from the local file, or downloads the object with a signed GET when no local file exists (upload-only captures), with a short notification while it downloads. Delete is the same single delete path as the overlay.

**Simpler delete confirmation.** The alert reads "Delete this capture?" with one line naming where the capture disappears from ("Removes it from object storage, your save folder and history." when a save-folder file exists, "Removes it from object storage and from history." otherwise) and two buttons, Delete and Cancel. Deleting implies removing the history entry. If the storage DELETE fails, a second alert offers "Remove from history anyway?" with Remove and Cancel, so a record whose object cannot be deleted is never stuck. The same second alert, with "The file stays where it is.", follows when the file in the save folder cannot be removed (it lies outside the current save folder, for example after another folder was chosen, or the folder's bookmark no longer resolves); any object this capture alone owned has been deleted by then (shared keys and pre-Phase 3 records keep theirs), so without it the record could never leave history. A second alert waits until no menu is open. The three-button alert from 2.4 is withdrawn.

**No `{app}` token.** Removed from both templates, the captions, and the README. Stored templates containing `{app}` are migrated by dropping the token and collapsing any doubled separator.

**Upload settings clarity.** Endpoint and Public URL fields show a neutral "Required" prompt; the example value sits in a caption under each field, so an unfilled field cannot be mistaken for a filled one. Save and Test Connection reports success without echoing the probe URL.

**Adaptive crosshair.** The selection crosshair samples the frozen snapshot under the cursor and draws black on light backgrounds and white on dark ones; before the snapshot arrives it is white with a one-pixel dark edge.

**Loupe crosshair (feedback after the Phase 3.1 build, 2026-10-20).** The cross inside the loupe stayed white, so over light pixels it vanished while the main crosshair turned black, and the 1 pt crosshair at 0.8 alpha was faint on any background. Both become two-tone strokes in the first task of Phase 4; see "Crosshair and loupe contrast" in 2.6.

### 2.6 Phase 4 design: the annotation editor (2026-10-20)

**Scope, order and release.** Phase 4 is one release delivered as two PRs on the branch `phase-4-annotation`.
- **4a (PR 1).** In order: the loupe and crosshair contrast fix; the editor model, rendering, undo and tools, with an end-to-end redaction export test; a window with Select, Redact, Pixelate, Blur, Rectangle and Arrow, the colour palette, line widths and zoom; the four actions (Save, Save Copy, Copy, and Upload with Upload as New); and the Annotate entry points on the Quick Access overlay and on Recent Captures rows. Redaction lands first because screenshots of dashboards and terminals carry secrets, and the 4a build can be used and tested before the drawing tools exist.
- **4b (PR 2).** Ellipse, Line, Pencil, Highlighter, Text and Crop, then keyboard polish (duplicate, object copy and paste, Space-drag pan) and canvas accessibility.
- **The Phase 4 release is 4a plus 4b.** Section 6 and the Annotate row (P1, "basic set plus blur, pixelate, redact") put ellipse, line, pencil, highlighter, text and crop in the first editor release next to the effects. The two PRs are an order of work, not a smaller first release.
- **4c (after the release, P2).** Spotlight, Counter, the editable project format, and "open editor" as an after-capture action (deferred from the 2.1 row: the overlay and Recent Captures cover the need in Phase 4, while a fourth after-capture action touches `save(_:)` and the Settings picker).

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

The coordinator side lives in `AppCoordinator.swift` itself, under `// MARK: Editor`. It has to, because it calls `private` (file-scoped) members: `makeThumbnail(from:for:)`, `showOverlay(for:image:scale:)`, `startUpload(recordID:data:destination:)`, `imageData(of:)`, `deleteObjects(_:at:)`, `removeRecord(id:)`, `removeFiles(ofPruned:)`, `refreshOverlay(for:)`, `notifier`, `overlay` and `deletingIDs`. Every branch the coordinator takes comes from a tested helper in `Editor/Persistence/`.

A new `nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }` (TidyShot/Output/ScaledImage.swift) is the only type that crosses between the editor and the coordinator. It exists because `CaptureResult` requires a MainActor `CaptureTarget`. `CaptureResult` gains `var scaled: ScaledImage`. The editor never writes files, never touches the pasteboard and never enqueues uploads. AppCoordinator stays the one save path, the one upload path and the one delete path.

**Concurrency rule.** Under `SWIFT_APPROACHABLE_CONCURRENCY` (NonisolatedNonsendingByDefault), a `nonisolated async` function runs on the caller's executor. Any nonisolated async function that must run off the main actor is therefore marked `@concurrent`. Detached tasks and actor methods are unaffected:
- `RedactionRenderer` is an actor, so its methods run on its own executor.
- `EditorModel.renderExport` flattens inside `Task.detached`.
- The test `FakeTileRenderer.tile` is `@concurrent` and waits on an async gate (an `actor TileGate` holding a `CheckedContinuation`), never on a `DispatchSemaphore`. A semaphore would block the main actor that the MainActor tile-cache tests run on, and deadlock.

**Document model.** All model geometry is in image pixels with a top-left origin (CGImage row 0). This is the same convention as `Luminance.mean(of:in:)` and `CGImage.cropping(to:)`.
- `RGBA` holds `red, green, blue, alpha: Double` in sRGB and derives `cgColor`. The model never stores a CGColor, CGPath, NSColor or CIFilter; CGPath and CIFilter are not Sendable in the 27 SDK.
- The payload structs are `ShapeBox { id: UUID; rect: CGRect; color: RGBA; lineWidth: CGFloat }`, `Segment { id; from: CGPoint; to: CGPoint; color; lineWidth }` and `Region { id; rect }`.
- `enum Annotation: Identifiable, Equatable, Sendable, Codable` has the 4a cases `rectangle(ShapeBox)`, `arrow(Segment)`, `redact(Region, fill: RGBA)`, `blur(Region, radius: CGFloat)` and `pixelate(Region, block: CGFloat)`. 4b adds `ellipse`, `line`, `pencil`, `highlighter` and `text`.
- Line widths, blur radii and block sizes are stored in image pixels: the points chosen in the UI times the capture scale at creation. Export therefore needs no conversion, and a 2x capture gets twice the pixels.
- `isEffect` is true for redact, blur and pixelate. Effects belong to the base layer: they render beneath every drawing, in creation order.
- `struct AnnotationDocument: Equatable, Sendable, Codable { var annotations: [Annotation] }` exposes `effects` and `drawings` (both in creation order), `annotation(id:)`, `appending(_:)`, `removing(id:)`, `replacing(_:)` and `moving(id:by:)`. 4b adds `crop: CGRect?` (decodeIfPresent).
- The base CGImage is not part of the document. EditorModel holds it next to the document and never mutates it.
- No file in Phase 4 persists the document. The only file on disk with unredacted pixels is the original the user chose not to overwrite. The clipboard rule below covers the one other copy.

**Rendering.** The window's content view stacks two viewport-sized views. There is no document-sized view and no NSScrollView magnification. This avoids `_NSTiledLayer` seams and a 10240x5760 backing store for a 5K capture.

*`BaseImageView`* is flipped and layer-backed, and its `hitTest` returns nil. It shows:
- the capture as one `CALayer.contents` texture, with implicit actions disabled;
- one sublayer per effect tile, in creation order, each framed at `transform.viewRect(rect)`.

Zoom and pan only move layer frames. All layers use `magnificationFilter = .nearest` when `zoom * backingScale >= 2` and `.linear` below, with `.trilinear` minification, so redacted pixels read exactly when zoomed in.

*`CanvasView`* sits on top. It is flipped and layer-backed, not opaque, with `layerContentsRedrawPolicy = .onSetNeedsDisplay`. Its `draw(_:)` works only within the dirty rect:
1. Concatenates `transform.affine`, so drawing is in image pixels.
2. Draws placeholders for pending effects: the fill colour for a pending redact, grey at 0.5 alpha for a pending blur or pixelate.
3. Draws every drawing whose bounds meet the dirty rect, then the transient shape, through `AnnotationDrawing.draw(_:in:scale:)`.
4. Restores the CTM, then draws selection handles (8 pt squares) and, for a selected effect, a dashed outline. Both are drawn in view space so they keep a constant size.

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

It uses no NSGraphicsContext, which is MainActor. Pixels outside the effects equal the base byte for byte. Alpha survives, so window captures keep their transparent corners. A solid redact over a transparent corner paints opaque pixels.

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

A new shape is selected after creation. 4b adds Ellipse (E), Line (L), Pencil (P), Highlighter (H), Text (T) and Crop (C). Each 4b tool task adds its case to `EditorTool` (the toolbar order comes from `EditorTool.toolbarOrder`), to `makeTool(for:)` in ToolFactory.swift, and to the tools group in EditorToolbar.swift.

**Palette and options.** The toolbar colour item shows the current colour as a filled circle. Its NSPopover (`.transient`) hosts `ColorPaletteView`: ten swatches (black, red, orange, yellow, green, teal, blue, purple, pink, white) plus `ColorPicker(supportsOpacity: false)`. Shapes use `strokeColor` (default red) and Redact uses `redactColor` (default black). The palette edits the colour of the active tool and of the selected annotation.

The options popover hosts `ToolOptionsView` with three controls:
- line width: 2, 3, 4, 6, 8 or 12 pt, also on keys 1 to 6, default 4 pt;
- blur radius;
- pixel block.

Changes apply live to the selection through a coalesced commit, so a slider drag is one undo step.

AppSettings persists five keys and adds no Settings tab: `editorStrokeColor` and `editorRedactColor` (RGBA as JSON Data), `editorLineWidthPoints` (4), `editorBlurRadiusPoints` (8) and `editorPixelBlockPoints` (10). They are read once into `EditorDefaults` when an editor opens.

**Undo.** EditorModel owns `let undoManager = UndoManager()` with `groupsByEvent = false`. UndoManager is MainActor-isolated in the 27 SDK, so no Sendable work is needed. `CanvasView.undoManager` and `windowWillReturnUndoManager(_:)` both return it, so `undo:` and `redo:` from the responder chain reach it.

The single write path is `commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String? = nil)`:
1. It wraps the registration in `beginUndoGrouping` and `endUndoGrouping`.
2. It registers a handler that re-commits the previous snapshot. That re-commit registers the inverse, which gives redo.
3. It calls `setActionName`, assigns `document` and calls `tileCache.reconcile`.

Coalescing works without timers. When `coalescingKey` equals the last commit's key, the document changes with no new registration, so a burst is one undo step. Arrow-key nudges use `"Nudge-<id>"` and a slider drag uses `"Blur Radius-<id>"`. The key is cleared by any other commit, by undo, by redo and by a selection change.

Selection, zoom, pan, tool and colour choice never enter the undo stack. `hasUnsavedChanges` is `document != savedDocument`. `markSaved()` runs after a successful Save, Save Copy or Upload local write, and `window.isDocumentEdited` mirrors the flag. A text edit in progress (4b) uses its own UndoManager, described below.

**Keyboard.**
- **Editor shortcuts.** The SwiftUI main menu of an LSUIElement app is never drawn, so editor shortcuts do not depend on it. `EditorWindow: NSWindow` overrides `performKeyEquivalent(with:)` and looks the event up in the pure table `EditorShortcut.match(characters:command:shift:option:control:isEditingText:)`. The key window sees key equivalents before the main menu, so nothing is handled twice. The 4a table:
  - ⌘S `saveDocument:`, ⇧⌘S `saveDocumentCopy:`
  - ⌘C `copy:`, ⇧⌘C `copyImage:`
  - ⌘U `uploadDocument:`, ⌥⌘U `uploadDocumentAsNew:`
  - ⌘Z `undo:`, ⇧⌘Z `redo:`
  - ⌘W `performClose:`
  - ⌘0 `zoomToFit:` and ⌘1 `zoomToActualSize:` (natural point size)
  - ⌘= `zoomIn:` and ⌘- `zoomOut:` (factor 1.25 around the view centre)
  - ⌘A `selectAll:`

  In 4a, `copy:` reaches EditorWindowController, which copies the flattened image, so ⌘C and ⇧⌘C behave the same. In 4b, CanvasView implements `copy:` for a selected object and passes it up the responder chain when nothing is selected, so the table does not change for ⌘C. 4b adds ⌘V `paste:` and ⌘D `duplicate:` and updates the table test in the same task. ⌘X has no row in any phase: Phase 4 has no object cut (rejectedIdeas), so ⌘X always goes to the responder chain.
- **Text editing bypass.** While a text annotation is being edited (`isEditingText`, 4b), `match` returns nil for the rows with `passesThroughWhileEditingText`: ⌘C, ⌘A, ⌘Z and ⇧⌘Z, plus ⌘V and ⌘D from 4b. Those keys then reach the NSTextView's own handling, as does ⌘X, which has no row. Save, Upload, Close and Zoom still match, and their controller actions first call `model.commitTextEditing()`.
- **Validation.** `NSApp.sendAction(_:to:from:)` does not consult `NSUserInterfaceValidations`. So on a match, EditorWindow:
  1. Resolves `NSApp.target(forAction:to: nil, from: self)`.
  2. If that target adopts NSUserInterfaceValidations, passes it a `ShortcutItem: NSObject, NSValidatedUserInterfaceItem` carrying the selector.
  3. When validation fails, beeps and consumes the event. Otherwise calls `NSApp.sendAction`.

  As a second guard, every action method on EditorWindowController (`saveDocument:`, `saveDocumentCopy:`, `copyImage:`, `uploadDocument:`, `uploadDocumentAsNew:`) re-checks the available set and returns at once when its `EditorAction` is missing. The pure `EditorCommandGate.action(for:)` maps each selector to an `EditorAction`, and `EditorCommandGate.permits(_:available:)` decides. Both are tested. The coordinator applies a third check at write time (see Record state).
- **Unmodified keys.** These reach `CanvasView.keyDown` only while the canvas is first responder. `KeyRouting.action(characters:command:control:option:isEditingText:)` maps tool letters and the digits 1 to 6. Everything else goes to `interpretKeyEvents`:
  - Escape and ⌘. become `cancelOperation:`, which abandons the drag and then deselects. It never closes the window.
  - Delete becomes `deleteBackward:` or `deleteForward:`.
  - The arrow keys become `moveLeft:` and its siblings, which nudge by `KeyRouting.nudge(dx:dy:shift:)`.
- **Pointer zoom and pan.** Pinch calls `magnify(with:)`, ⌘-scroll zooms around the cursor, and plain scroll pans. Zoom limits are `0.1 / captureScale ... 8 / captureScale`, and offsets snap to device pixels. Tooltips show each tool's letter.

**Window.**
- **Shape.** `EditorWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations` runs one window per record. AppCoordinator holds the controllers in `editors: [UUID: EditorWindowController]`. The window is an `EditorWindow` with:
  - style mask `[.titled, .closable, .miniaturizable, .resizable]` and `toolbarStyle = .unified`;
  - normal level, managed collection behaviour plus `.fullScreenPrimary`, and `tabbingMode = .disallowed`;
  - `representedURL` set to the file when one exists, and `title` set to the file name or `Capture <time>`;
  - `subtitle` showing the status line from `EditorAvailability.status`, for example `Uploading…`, `Deleting…`, `The uploaded copy still shows the original. Upload to replace it.` or `This capture was deleted. Copy and Save Copy still work.`
- **Size and placement.** There is no frame autosave. `EditorWindowGeometry.initialContentSize(imagePixels:scale:chrome:visibleFrame:)` sizes the window to the image's natural point size plus chrome and a 24 pt inset. The size is at least 640x420 and at most 90% of the visible frame of the screen under the mouse. The transform starts at `CanvasTransform.fitting(imagePixelSize:in:inset: 24, captureScale:)`, never above natural size. Later editors are placed by `EditorWindowGeometry.cascaded(from:size:visibleFrame:)`, 22 pt down and to the right, clamped to the screen.
- **Showing.** `present()` calls `NSApplication.shared.activate(ignoringOtherApps: true)`, then `makeKeyAndOrderFront(nil)`, then `orderFrontRegardless()` if the app is still inactive. This is the codebase's proven idiom: a plain `activate()` is refused when called from the non-activating overlay.
- **Toolbar** (EditorToolbar.swift). `NSToolbar(identifier: "AnnotationEditor")`, `.iconOnly`, no customisation. The items, in order:
  - `.tools`: an `NSToolbarItemGroup` with images, `.selectOne` and `controlRepresentation = .automatic`, built from `EditorTool.toolbarOrder`;
  - `.space`, `.color`, `.toolOptions`, `.flexibleSpace`;
  - `.zoom`: a pop-up with Fit, 50 %, 100 %, 200 % and 400 %;
  - `.copyImage`;
  - `.save`: an `NSMenuToolbarItem` whose menu offers Save Copy…;
  - `.upload`: an `NSMenuToolbarItem` with `style = .prominent`, whose menu offers Upload and Upload as New.

  Liquid Glass comes free, so there are no custom backgrounds.
- **Closing.** `windowShouldClose(_:)` returns false while `hasUnsavedChanges` and runs `askToSaveBeforeClosing() async -> Bool` as an NSAlert sheet:
  - message: `Do you want to save the changes made to “<title>”?`
  - informative text: `Your changes will be lost if you don’t save them.`
  - buttons: Save (or Save Copy… when Save is unavailable), Cancel, and Don’t Save (⌘D).

  Quitting does not call `windowShouldClose`. So `AppDelegate.applicationShouldTerminate(_:)` returns `.terminateLater` while any editor is dirty and calls `AppCoordinator.reviewEditorsBeforeQuit() async -> Bool`. On close, the controller tells the coordinator. The coordinator drops the registry entry and, when no editor is left, calls `RedactionRenderer.shared.clearCaches()`.
- **Record state.** One coordinator helper, `pushEditorState(for id: UUID)`, calls `editors[id]?.recordDidChange(history.record(id: id), saveFolder: saveLocation.currentURL, isDeleting: deletingIDs.contains(id))`. A nil record means deleted or pruned. These call it:
  - `refreshOverlay(for:)`, so every upload progress, success, failure and retry reaches the editor;
  - `removeRecord(id:)`;
  - `removeFiles(ofPruned:)`, for each pruned record, because retention pruning goes through `didPrune` and not through `removeRecord`;
  - `deleteCapture(recordID:)`, right after `deletingIDs.insert` (AppCoordinator.swift:538) and again from its `defer` after `deletingIDs.remove`. While the delete alert, `cancelUpload`, `deleteObjects` and the second alert are pending, `EditorAvailability.actions(record:saveFolder:isDeleting: true)` leaves only Copy and Save Copy;
  - `editorUpload`, after its own `history.update` sets `.uploading(0)`. `startUpload` calls `refreshOverlay` only for a record that is not already uploading (AppCoordinator.swift:385-388), so without this the editor would learn of the upload only at the first progress event.

  Save-folder changes are pushed too. While any editor is open, the coordinator observes `saveLocation.currentURL` (SaveLocation is `@Observable`). It uses the `withObservationTracking { } onChange: { Task { @MainActor in … } }` idiom from StatusMenuController and re-registers on each change. A change calls `pushEditorState` for every open editor, so Save availability and the subtitle follow a folder chosen in Settings. Safety does not depend on this push: `EditorSaveTarget.plan` is recomputed from the current record and folder at write time.

  The same set drives the toolbar items and the shortcut gate. `editorSave`, `editorUpload` and `editorSaveCopy` also re-check, at write time and on the coordinator side, `EditorAvailability.refusal(for:record:saveFolder:isDeleting:)`. They use `history.record(id:)` and `deletingIDs.contains(id)` read at that moment. A non-nil reason posts `notifyError(reason, title: "Not saved")` (or `"Not uploaded"`) and writes nothing. A Save racing a delete therefore never recreates a pending or thumbnail file for a removed record.

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
- `.unavailable(reason)` for a record with no local file, a file outside the current folder, or no folder. Save is then disabled, and Save Copy and Upload remain.

Save and Upload are disabled while the record is uploading or being deleted. Save never touches the network. On an uploaded record, `uploadIsStale` drives the subtitle `The uploaded copy still shows the original. Upload to replace it.` A failed write posts `notifyError(..., title: "Not saved")` and puts the edited image on the clipboard, so an edit is never dropped.

**Clipboard rule (secrets).** `save(_:)` copies the original image when `copyImageNow` is true (AppCoordinator.swift:171-183). That happens in three cases:
- Save mode with "Copy image to clipboard" on (the default);
- Upload or Upload-only mode with "Also copy image";
- an upload action with no destination configured, where the image goes to the clipboard instead of a URL.

The `keepOnClipboard` failure paths also copy it, but they return before a record exists, so no editor can open for that image. After a redaction, the original would stay on the clipboard. To prevent that:
- `Pasteboard.copy` now returns the pasteboard's `changeCount`.
- The coordinator keeps `clipboardOwner: (recordID: UUID, changeCount: Int)?`. `save(_:)` sets it whenever `copyImageNow` is true, and the editor's Copy also sets it.
- After a successful local edit or Save Copy, the coordinator replaces the clipboard with the edited PNG and TIFF when `EditorClipboard.shouldReplace(owner:recordID:currentChangeCount:)` holds. That means the clipboard still holds exactly what TidyShot put there for this record. Anything the user copied since is left alone.
- An Upload's `.uploaded` handler then copies the URL as the last write, as it does today.

**Save Copy (⇧⌘S).** The tail of `save(_:)` is factored into `persist(png: Data, image: ScaledImage, action: AfterCaptureAction, destination: S3Destination?, options: PersistOptions) async -> CaptureRecord?`, where `PersistOptions { baseName: String?; alreadyOnClipboard: Bool; playsSound: Bool }`. It writes the file, warns once when upload is not configured, plays the sound, records the capture, makes the thumbnail, shows the overlay, and starts the upload or posts notifySaved. Both `save(_:)` and Save Copy call it, so there is still one save path. `writeFile`, `writePendingFile` and `keepOnClipboard` take `ScaledImage` instead of `CaptureResult`.

Save Copy creates a new CaptureRecord that follows `settings.afterCaptureAction`:
- It gets a new file in the save folder, or a pending file that uploads in upload-only mode, plus a thumbnail, a Recent Captures row and the overlay.
- There is no shutter sound, and the clipboard changes only through the clipboard rule.
- The file name is `EditorNaming.copyBaseName(for:)`, which returns `<original stem> edited`, made unique by `FileNamer.uniqueURL`. When the original has no file, the name comes from the template, with `{counter}` drawn as for a capture.
- The editor stays on the original record and calls `markSaved()`. A deleted or pruned original does not block Save Copy.

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
- **Local write first.** Before any upload, the coordinator runs `applyLocalEdit`, so the file equals the object. For a record with no local file, it writes `pending/<id>.png` and sets `fileURL` and `fileIsTemporary = true`. Retry and Delete then see the file, and `handle(.uploaded)` removes it as today. A save-folder file outside the current folder is not rewritten; the upload still proceeds, and the subtitle says so.
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
- **Lane.** Every editor upload goes through the live lane, so cancel, progress, `uploadingIDs`, Delete and the menu bar icon keep working. The URL copy on `.uploaded` is always the last clipboard write.

**Thumbnails after an edit.** An edited thumbnail gets a new name, `ThumbnailStore.fileName(for:editedAt:)` = `<UUID>-<milliseconds>.png`, written by the new `ThumbnailStore.write(_:fileName:)`. The previous file is removed. `RecentCaptureRow` reloads on `.task(id: record.thumbnailFileName)`, so rows refresh without further work.

Neither older writer can clobber an edited thumbnail:
- The capture-time `makeThumbnail` and the legacy `ThumbnailProvider` path only ever write `<UUID>.png`.
- A late `makeThumbnail` checks `record.editedAt == nil` before naming its file on the record, and otherwise deletes the file.
- ThumbnailProvider needs no change: its `forget` bumps the generation, so a late legacy write is discarded.

`CaptureRecord.editedAt: Date?` and `uploadIsStale: Bool` (both decodeIfPresent) drive the subtitle note.

**Phase 4b.**
- Ellipse and Line.
- Pencil, with decimated points and Catmull-Rom smoothing. Hit testing strokes a CGPath built on the fly.
- Highlighter: multiply blend, yellow at 0.45 alpha.
- Text: an NSTextView subview of CanvasView, positioned by the transform.
  - Its delegate's `undoManager(for:)` returns a private UndoManager for the edit, so typing never registers into the editor's `groupsByEvent = false` manager. Committing the text is one editor commit, and the private manager is then discarded.
  - `isEditingText` turns off tool letters and the pass-through chords in EditorShortcut.
  - Committed text is drawn with CoreText on the bare CGContext, with a flipped text matrix.
- Crop: `document.crop` with 8 handles, a dim mask and a W x H readout. Return applies and Escape cancels. The crop is undoable, is applied last at export, and updates the pixel size on Save.
- ⌘D and ⌥-drag duplicate; object copy and paste; Space-drag pan; canvas accessibility elements.
- A 4b checklist, a README section and a totals check.

**Phase 4c (later, P2).**
- Spotlight and Counter.
- The `.tidyshot` project package. It is local only and never uploaded, and a warning says it keeps the unredacted original.
- The after-capture open-editor option.

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
- Menu bar on `NSStatusItem` + `NSMenu`; Recent Captures hover submenu with custom rows (thumbnail, name, relative time, copy URL, copy image, delete) and a floating preview on the side of the submenu away from the status menu (the other side when there is no room, always on screen); gallery window removed.
- `S3Destination.download(key:)` (signed GET) for copy-image on upload-only captures.
- Two-button delete alert, with a "remove from history anyway" fallback only after a failed storage DELETE or a save-folder file that cannot be removed.
- `{app}` token removed with migration of stored templates.
- Upload tab: "Required" prompts with example captions; connection test result without the probe URL.
- Adaptive crosshair colour from the snapshot.

### Phase 4: annotation (1 to 2 weeks)
Design in 2.6. One release in two PRs.
- 4a: crosshair and loupe contrast; editor window with Select, Redact, Pixelate, Blur, Rectangle, Arrow, undo, colour palette, line widths and zoom; Save over, Save Copy, Copy, Upload (same key) and Upload as New; Annotate on the overlay and on Recent Captures rows.
- 4b: Ellipse, Line, Pencil, Highlighter, Text, Crop; duplicate, object copy and paste, Space-drag pan, canvas accessibility.
- 4c (later): spotlight, counter, an editable project format, and "open editor" as an after-capture action.

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
