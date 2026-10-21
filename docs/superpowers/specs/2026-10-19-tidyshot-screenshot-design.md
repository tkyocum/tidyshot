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
| Scrolling capture | Captures content taller than the screen, any app | P1 (own phase) | Hardest screenshot feature; gets Phase 5, designed in 2.8. Manual mode first (the user scrolls, TidyShot captures and stitches; Screen Recording only), then opt-in auto-scroll that posts scroll-wheel events behind the PostEvent permission (listed as Accessibility in System Settings). Vertical only; horizontal is deferred |
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
- **4c (after the release, P2).** Spotlight, Counter, the editable project format, and "open editor" as an after-capture action (deferred from the 2.1 row: the overlay and Recent Captures cover the need in Phase 4, while a fourth after-capture action touches `save(_:)` and the Settings picker).

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

The coordinator side lives in `AppCoordinator.swift` itself, under `// MARK: Editor`. It has to, because it calls `private` (file-scoped) members: `makeThumbnail(from:for:)`, `showOverlay(for:image:scale:)`, `startUpload(recordID:data:destination:)`, `imageData(of:)`, `deleteObjects(_:at:)`, `removeRecord(id:)`, `removeFiles(ofPruned:)`, `refreshOverlay(for:)`, `notifier`, `overlay` and `deletingIDs`. Every branch the coordinator takes comes from a tested helper in `Editor/Persistence/`.

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
- the capture as one `CALayer.contents` texture, with implicit actions disabled;
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
- **Size and placement.** There is no frame autosave. `EditorWindowGeometry.initialContentSize(imagePixels:scale:chrome:visibleFrame:)` sizes the window to the image's natural point size plus chrome and a 24 pt inset. The size is at least 640x420, at least the toolbar's width, and at most 90% of the visible frame of the screen under the mouse. The toolbar's width comes from `EditorWindowGeometry.toolbarWidth(windowButtonsMaxX:titleWidth:toolSegments:buttons:prominentButtons:viewWidths:fixedSpaces:)`: the window buttons and the title (counted up to 96 pt, since a unified toolbar truncates its title first) are measured, the zoom pop-up has a fixed width, and the items AppKit draws itself use `EditorWindowGeometry.ToolbarMetrics`. `toolSegments` is `EditorTool.toolbarOrder.count`, one 36 pt segment per tool, so the 4b toolbar with twelve tools and the widest title is 1016 pt (the 4a toolbar was 800), within 90% of a 1280 pt display; `toolbarWithEveryToolFitsASmallDisplay` pins both numbers. `minimumContentWidth(toolbarWidth:)` (at least 640) becomes `contentMinSize.width` and the initial size's minimum, so the window never gets narrow enough for the overflow chevron. The transform starts at `CanvasTransform.fitting(imagePixelSize:in:inset: 24, captureScale:)`, never above natural size. Later editors are placed by `EditorWindowGeometry.cascaded(from:size:visibleFrame:)`, 22 pt down and to the right, clamped to the screen.
- **Showing.** `present()` calls `NSApplication.shared.activate(ignoringOtherApps: true)`, then `makeKeyAndOrderFront(nil)`, then `orderFrontRegardless()` if the app is still inactive. This is the codebase's proven idiom: a plain `activate()` is refused when called from the non-activating overlay.
- **Toolbar** (EditorToolbar.swift). `NSToolbar(identifier: "AnnotationEditor")`, `.iconOnly`, no customisation. The items, in order:
  - `.tools`: an `NSToolbarItemGroup` with images, `.selectOne` and `controlRepresentation = .automatic`, built from `EditorTool.toolbarOrder`: in 4b twelve tools, Select, Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text and Crop, each with a tool tip such as `Ellipse (E)`;
  - `.space`, `.color`, `.toolOptions`, `.flexibleSpace`;
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

**Phase 4c (later, P2).**
- Spotlight and Counter.
- The `.tidyshot` project package. It is local only and never uploaded, and a warning says it keeps the unredacted original.
- The after-capture open-editor option.

### 2.7 To-do: optimise images with Clop before upload (2026-10-20)

**Request.** Dropshare's Images setting "Optimize images with Clop" (a checkbox with the caption "Clop is an image optimizer that greatly reduces file size.") shrinks images before they upload. TidyShot gets the same option for people who have [Clop](https://lowtechguys.com/clop) installed. Tim owns the paid version.

**Integration.** [ClopSDK](https://github.com/FuzzyIdeas/ClopSDK) is an MIT-licensed Swift package that sends files to the running Clop app over a local Mach port (`com.lowtechguys.Clop.optimisationService`) and returns an `OptimisationResponse` (`path`, `oldBytes`, `newBytes`, sizes). Its main call is `optimise(url:aggressive:downscaleTo:...:hideGUI:copyToClipboard:inTheBackground:) throws`; `waitForClopToBeAvailable(for:)` checks that Clop is reachable. The Clop app itself is GPLv3; TidyShot only talks to it and never reads or copies its code, which keeps decision 7.

**Behaviour.**
- **Setting.** The Upload tab gains "Optimize images with Clop" with the caption above, off by default. It is enabled only when Clop is installed (`/Applications/Clop.app`, `/Applications/Setapp/Clop.app`, or a running app whose bundle identifier starts with `com.lowtechguys.Clop`). Otherwise the box is disabled, with a link to the Clop site.
- **When.** After the PNG is written and before the PUT, the coordinator hands Clop a copy in the container, with `hideGUI: true` and `copyToClipboard: false`, and uploads the bytes Clop returns. The save-folder file stays as captured. The uploaded object and an upload-only pending file are optimised.
- **Annotated images too.** Uploads from the editor (Upload, the same-key replace, Upload as New, and a Retry of any of them) go through the same step, so an annotated screenshot is optimised exactly like a fresh capture. The edited file the editor saves locally stays unoptimised, as a capture's save-folder file does.
- **Never lose a capture.** Clop is unavailable after a short wait, an optimisation throws or times out, or the result is larger: TidyShot uploads the original bytes, logs why, and posts no error.
- **Format.** If Clop converts the file (its own settings can turn PNG into JPEG), the object key's extension and the Content-Type follow the returned file.

**Open questions, settle before planning.**
1. **Sandbox.** A sandboxed app cannot look up another app's Mach port without `com.apple.security.temporary-exception.mach-lookup.global-name` for the port names. That is the first new entitlement since Phase 0 and amends the "no new entitlements" constraint. Verify whether it is needed, and whether it blocks a future Mac App Store build.
2. **File access.** Clop must read the file TidyShot hands it. A file inside TidyShot's container may trigger macOS's prompt for one app reading another app's data. Test this, and if it prompts, hand Clop a file in a location it can read without asking.
3. **Output path.** The SDK passes an optional output path; check whether Clop optimises in place or writes beside the original, and where.
4. **DPI.** Check whether optimised PNGs keep the 144 DPI metadata; browsers ignore it, but a pasted image would show at double size without it.
5. **Licensing.** Confirm whether SDK requests need Clop Pro.
6. **Dependency.** ClopSDK becomes the second Swift package, which amends the "KeyboardShortcuts as the only package" constraint.

**Placement.** About a day of work once the open questions are settled. It sits with the Phase 7 extras but can be pulled forward after Phase 4b.

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
- either, height cap: `Reached the 16,384 pixel limit.`
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
8. *Change in place.* When no candidate is accepted but the leading or the trailing run of equal rows of step 2 is longer than `maxStaticFraction` of the height, longer than any header or footer can be, part of the band stayed put: nothing scrolled, and the rows between changed in place (Terminal output in a window not yet full, a new chat message that does not scroll the list). The result is `.still`, not `.lost`, so manual mode does not show the too-fast line and the stitcher commits nothing, and auto mode counts it as a still. A jump past the band changes the whole band and stays `.lost`.

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

**One save path.** `AppCoordinator.captureScrolling()` runs inside `withCaptureLock`: `loadContent()`, then `selector.select(mode: .scrolling, content:)`, `selector.dismiss()`, then `scrollCapture.run(rect:display:)`. An `.image` (or a `.failed` with a partial image) becomes `CaptureResult(image:scale:target: .area(rect:display:))` and goes to `save(_:)` unchanged: the after-capture action, the file or pending file, the history record, the thumbnail, the Quick Access overlay with Annotate, and the upload all behave as for any capture (`CaptureResult.target` is read nowhere downstream). Two changes in `save(_:)` keep a tall capture from blocking the main actor: the PNG encode, and the TIFF for the clipboard when `copyImageNow` holds, run in `Task.detached(priority: .userInitiated)`, and the clipboard write uses `Pasteboard.copy(pngData:tiffData:)`. Every capture takes that path; for a normal capture the cost is one hop.

**Preview before save or upload.** The live preview in the panel is the preview section 6 asks for: nothing is written, recorded or uploaded until Done, and Cancel or Escape discards everything. After Done the normal Quick Access overlay follows, with Annotate and Delete, so a bad result is fixed or removed in two clicks. A separate review window between Done and save is not built (Decisions).

**Height cap and tall images.** `ScrollCaptureLimits.maxPixelHeight` is 16,384 px (8,192 pt at 2x). The editor shows a capture as one `CALayer.contents` texture (2.6, Rendering); Metal accepts 32,768 px on the M5 Max and 16,384 on older Apple GPUs, so 16,384 keeps Annotate working on any Apple Silicon Mac. At the cap and 2560 px wide the output is 168 MB of pixels, plus two 20 MB frame copies. For the 96x72 overlay well and the 320 px thumbnail, `ThumbnailMaker.thumbnail(from:maxSide:)` gains a top crop: an image taller than 3 times its width is cut to its top `width * 3 / 2` rows before scaling, so the thumbnail shows the start of the page instead of a sliver (`ThumbnailMaker.cropForThumbnail(_:)`, pure, tested). The ImageIO path (`thumbnail(from source:maxSide:)`, for a record whose thumbnail is not written yet and for the Recent Captures hover preview) crops the same way: it reads the pixel size with `CGImageSourceCopyPropertiesAtIndex` and, when the crop would cut, decodes the image, cuts it to the top and draws that. The record's `pixelWidth` and `pixelHeight` are the full size.

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

The selection overlay, the panel, the stream and real event posting are covered by `docs/testing/phase-5-manual-checklist.md`: Safari, Chrome, Slack (a long channel), Notes, Finder list view, Terminal and Xcode; a site with a sticky header and a cookie footer; dark mode; natural scrolling on and off; two displays at mixed scales; Escape with another app frontmost; a too-fast flick and recovery; the 16,384 px cap; the permission flow, including re-granting after an ad-hoc rebuild; Upload-only mode end to end; Annotate on a capture at the cap; and a one-shot area capture of the same region compared pixel for pixel with the stitched image's first screen.

**Risks.**
- *Auto-scroll delivery (hand check open at delivery, 2026-10-21).* The driver, the poster and the permission flow are built and tested against fakes; whether a wheel event posted at the HID tap reaches Safari, Terminal and a chat window after the grant has not been observed yet. If it fails, the fallback view exists (`ScrollCaptureSession.isAutoScrollAvailable`, false without an environment: the checkbox stays visible, off and disabled, with the caption `Auto-scroll is unavailable: macOS did not deliver TidyShot's scroll events.` in place of the Allow Auto-Scroll… link, and manual mode is unaffected), and turning it on is a one-line change in `ScrollCaptureController` (pass `nil` as the session's `autoScrollEnvironment`). Replace this bullet with the observed result after the checklist's permission section is run.
- *Grant loss on rebuild.* Ad-hoc signing (Config/Local.xcconfig on Tim's Mac) loses the PostEvent grant on every build, often leaving a stale switch on in System Settings; remove the entry and add it again, or sign with Apple Development.
- *Content the finder cannot place.* A blank stretch taller than the area, a page of identical rows, or animation across the whole width leaves no informative overlap. Manual mode shows the too-fast line until overlap returns; auto mode reads the blank stretch as still and ends there. A jump past the band in an area whose top or bottom 40 % does not change (a static pane, or a blank stretch at the same rows in both frames) reads as a change in place, `.still`: manual mode then shows no too-fast line, and auto mode counts a still instead of a loss.
- *Fixed overlays inside the band* (a floating chat button, a sidebar scrolling at a different speed) are stitched in each time they appear. The checklist records what Safari and Chrome do with them.
- *Lazy loading and infinite scroll.* The 700 ms retry covers most loads; an infinite feed runs to the cap.
- *Wrong pane.* Wheel events go to the view under the pointer; with several panes in the area, the user points at the one to scroll.
- *Memory and time at the cap.* 168 MB of pixels, about 0.2 s and more to encode (off the main actor), and a 168 MB texture in the editor.
- *Colour.* If `colorSpaceName` from `CGDisplayCopyColorSpace` is refused, the stream falls back to sRGB, and the checklist comparison with a one-shot capture shows the difference.

**Deferred.** Horizontal scrolling (the finder transposes cleanly, but the panel, the end detector and the event poster need a direction, and wide content is rare); scrolling up to capture content above the start; a window-only filter with transparent corners; a self-timer before Start; scrolling capture in the URL scheme (`tidyshot://capture-scrolling`, Phase 6); a review window between Done and save; raising the cap above 16,384 px.

**Decisions (defaults chosen 2026-10-21, confirmed in the plan PR).**

1. **Manual mode first, auto-scroll second in the same phase.** Recommended. The sandbox allows auto-scroll, but delivery has not been observed here yet and an ad-hoc rebuild drops the grant, so manual mode is the part that always works. Alternative: auto first, as section 6 has it.
2. **Height cap 16,384 px** (8,192 pt at 2x). Recommended: Annotate keeps working because the editor's single texture stays within every Apple GPU's limit. Alternative: 32,768 px, which the M5 Max accepts, after a checklist run shows the editor rendering a capture that tall.
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
- Not done in code, by decision: no entitlement and no `project.yml` change (the diff of both against `main` is empty); the delivery fallback of the Risks list is built but not switched on (see the first Risk).
- Observations from the checklist run are still to be written down here by Tim: what Safari and Chrome do with the fixed spinner, footer and overlay scrollbar; the time at the 16,384 px cap and from Done to the overlay; natural scrolling, from halfway and from the top; the stitched-versus-one-shot comparison and the profile and DPI; how the editor behaves at 16,384 px; what a chat's typing dots do; and whether PostEvent delivery works (see the first Risk). None of the GUI checks had been run when this was written.

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
- 4a: crosshair and loupe contrast; editor window with Select, Redact, Pixelate, Blur, Rectangle, Arrow, undo, colour palette, line widths and zoom; Save over (or Save As… with no file), Save As…, Copy, Upload (same key, closing the editor) and Upload as New; Annotate on the overlay and on Recent Captures rows.
- 4b: Ellipse, Line, Pencil, Highlighter, Text, Crop; duplicate, object copy and paste, Space-drag pan, canvas accessibility.
- 4c (later): spotlight, counter, an editable project format, and "open editor" as an after-capture action.

Delivered 2026-10-20: 4a in PR 7 (merge commit 9193586) and 4b in PR 2 on `phase-4b-annotation`. Phase 4 is released when PR 2 merges. Design and what was built: 2.6.

### Phase 5: scrolling capture (1 to 2 weeks)
Design in 2.8.
- Vertical scrolling capture of an area or window: manual mode first (the user scrolls, TidyShot captures and stitches), with a live preview, Done, Cancel and an automatic end.
- Then auto-scroll on the same engine, behind the post-event permission flow.
- Later: horizontal scrolling.

Delivered 2026-10-21: manual and auto-scroll on `phase-5-scrolling`. Phase 5 is released when its PR merges. Design and what was built: 2.8.

### Phase 6: overlay and capture polish (2 to 3 days)
- Full overlay: save-as, drag-out, close and restore, stacking, multi-display.
- All-in-One mode and capture-previous-area.
- Freeze screen, self-timer, cursor and shadow options, window shot with transparent background.
- Pin to screen.
- URL scheme (`tidyshot://capture-area?action=upload` and friends).

### Phase 7: extras (as wanted)
- Optimise images with Clop before upload (see 2.7); can be pulled forward after Phase 4b.
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
