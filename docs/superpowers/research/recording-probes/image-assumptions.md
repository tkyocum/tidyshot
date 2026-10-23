# Where TidyShot assumes a capture is an image (map, 2026-10-22, branch phase-7c-background)

All paths are under TidyShot/. Line numbers are approximate.

## 1. Upload path

The whole path works on `Data` held in memory.

- `Upload/Destination.swift:12`: `upload(_ data: Data, key:contentType:cacheControl:progress:)`.
- `UploadJob` (`Destination.swift:30-74`): `let data: Data`, plus `contentType` and `fileExtension`. Two inits: template (:53) and fixed key (:65, `no-cache`). `UploadError.fileUnreadable` exists. Retryable errors are status >= 500, 429, or a URLError that is not cancelled.
- `UploadQueue.swift`:
  - `enqueue` :61.
  - `drain` is strictly serial (:91-100), so a big video blocks later uploads.
  - `destination.upload(job.data…)` :112.
  - Progress events are not throttled (:114).
  - The retry loop re-sends the whole body (:124-138).
  - `RetryPolicy`: 3 attempts.
  - Keys: `reserveKey(ext: job.fileExtension)` with a HEAD check and up to 5 tries (:157-175).
- `S3Destination.swift`:
  - Headers :56-73.
  - The payload hash is `S3Signer.sha256Hex(body)`, one-shot (:106; `S3Signer.swift:179`). There is no streaming hash and no UNSIGNED-PAYLOAD.
  - The body is sent with `session.upload(for:from: data)` (:68), from memory, not from a file.
  - The session is ephemeral (:18-22).
  - `download(key:) -> Data` (:87-95) buffers the whole object.
- `UploadProgressDelegate` reports progress as bytes sent / expected.
- `ConnectionTester` already uploads with ext `txt` and type `text/plain`.
- `AppCoordinator.startUpload` (:1015-1069):
  - :1034 and :1039 hard-code `image/png` and `png`.
  - The Clop path :1042-1068 holds the `data` while it waits.
  - `optimisedForUpload` :1082 calls `ClopOptimiser.optimisedPNG` (`Upload/ClopOptimiser.swift:53`). The work file is `<UUID>.png` (:65), and the PNG checks are at :94-96, :114 and :120.
- Retry: `retryUpload` :1093, `retryFailedUploads` :1105, then `retry` :1120, then `readLocalFile` :1124/:1146, which returns `Data` (pending file via `Data(contentsOf:)`, or `saveLocation.read`).
- `HistoryStore.swift:56-59`: `.uploading` at launch becomes `.failed("Upload was interrupted.")`.
- `.uploaded` handling (AppCoordinator :1552-1595): the pending file is adopted into the drag folder or removed, then `Pasteboard.copy(url:)` and `notifyUploaded`.
- Tests that build `UploadJob` or a fake `Destination`: UploadQueueTests, S3DestinationTests, ClopOptimiserTests, ConnectionTesterTests.

## 2. History

- `History/CaptureRecord.swift:5-50`: `id`, `timestamp`, `fileURL` ("the PNG"), `fileIsTemporary`, `thumbnailFileName`, `pixelWidth`/`pixelHeight` (non-optional Int), `appName`, `uploadState`, `objectLocation`, `pendingObjectKey`, `editedAt`, `uploadIsStale`, `supersededObjects`, `priorUpload`. There is no media kind and no duration.
- Pattern for a new field: add it to `CodingKeys` (:74-78), add a defaulted parameter to the init (:52-72), and decode it with `decodeIfPresent(...) ?? default` in `init(from:)` (:84-101). Legacy tests are in CaptureRecordTests.
- `HistoryStore.swift:40-54`: one undecodable record makes the whole file get set aside. Pruning keeps pending-only, unuploaded-edit and uploading records.
- Thumbnails: `AppCoordinator.makeThumbnail(from: CGImage, for:)` (:850-871) takes any CGImage, so it can take a poster frame. `ThumbnailMaker.cropForThumbnail` cuts images taller than 3× their width to the top. `ThumbnailStore` names are `<UUID>.png`.

## 3. Persist

- `AppCoordinator.save(_ result: CaptureResult, intent:)` (:621-679) is image-only:
  - `withWindowBackground`, `copyOnly`, the PNG and TIFF encode, `copyImageNow`, `Pasteboard.copy(pngData:)`;
  - `latestCaptureArea` and `clipboardOwner`;
  - `intent.then` `.annotate`/`.pin`.
- `persist(png:image:action:destination:alreadyOnClipboard:captureDisplayID:)` (:746-793):
  - writes the pending or save-folder file;
  - plays the shutter :766;
  - builds the `CaptureRecord` (:779-781);
  - `makeThumbnail` :783, `showOverlay` :784, `startUpload(data: png)` :787, `notifySaved` :790.
- `writeFile` (:807-823): `FileNamer` then `saveLocation.write(png, baseName:, ext: "png", in:)` (:816). `SaveLocation.write(_ data: Data…)` (`Output/SaveLocation.swift:54-60`) uses `FileNamer.uniqueURL`. There is no copy or move of a file into the save folder.
- `writePendingFile`: `pendingFiles.write(png, id:, ext: "png")` (:829). `PendingFileStore.write(_ data:id:ext:)` names the file `<id>.<ext>`.
- Other png write sites: :2058, :2230.
- `Pasteboard.copy(fileURL:)` exists (:70).
- Notifications: `notifySaved` defaults to the title "Screenshot saved". "Image copied" at :735, :1188, :2355; "Copying image…" at :1270.
- `showOverlay(for:image: CGImage?…)` (:873-884) sets `latestCapture` to the image it is given (:883). The editor then treats `latestCapture` as the retained image (`EditorInput.source .retained`), so a video poster passed there would let Annotate or Save write PNG bytes over the `.mp4`. Pass `image: nil`, or keep the card thumbnail separate from `latestCapture`.

## 4. Quick Access card (Overlay/)

- `QuickAccessView`: the card is 340×104 with a 96×72 thumbnail well and a "photo" placeholder.
- Status text comes only from the upload state (Uploading… with progress, URL copied, Upload failed, Saved). There is no size or duration label.
- Actions:
  - Annotate (:19-27, menu :88): image-only.
  - Pin (:28-36, :89): image-only.
  - Delete: generic.
  - Copy URL (menu :84, button :103): generic.
  - Copy Image (menu :86): image-only (`copyImage` AppCoordinator:1175, which PNG-decodes).
  - Save As… (:109, :87): `saveAs` :1197, then `saveCopy` :1206, then `EditorNaming.savePanel` (PNG only), then `imageData`, then `writeSaveAsCopy(png)` :2169. Image-only.
  - Retry: generic.
  - Reveal: generic.
- `QuickAccessModel.isSettled = !record.isUploading`, so a long upload keeps the card open.
- Drag-out (`QuickAccessCardDragSource.swift:68`) uses a file URL, so it works for any file type.

## 5. Recent Captures

- `RecentCaptureRow` actions: copyLinkOrFile (generic), annotate, copyLink, copyImage, delete.
- `RecentCaptureFormatting.canCopyImage` and `canAnnotate` have no media check.
- `ThumbnailProvider.preview(for:)` (:100-125) reads the whole local file on every hover and PNG-decodes it, then falls back to the thumbnail. `thumbnail(for:)` (:51-93) reads and decodes the file when there is no stored thumbnail.
- `PreviewPanel` is a static `NSImageView`.

## 6. Editor and Pin

- `openEditor` (:1797) goes through `EditorInput.source` (`Editor/Persistence/EditorInput.swift:37-48`): `.retained`, `.pendingFile`, `.saveFolderFile`, `.download` or `.unavailable`. It has no media check. Add `.unavailable` for videos.
- `loadImage` (:1830) and `ImageEncoder.decode`.
- Editor save:
  - `applyLocalEdit` (:2041) goes through `EditorSaveTarget.plan` to `SaveLocation.overwriteScoped`. For a video record this would overwrite the MP4.
  - `editorUpload` (:2199).
- Pin (:1856): `latestCapture` or `loadImage`, then `PinController.open(image:)`. Image-only.

## 7. Drag-out

- `Output/DragFileStore` is file-based and works for any extension.
- `Overlay/DragFileName.swift:19-20` appends `.png` when the name lacks it, so `abc.mp4` becomes `abc.mp4.png`. With no key, the name comes from `EditorNaming` (`+ ".png"`).
- `prepareDragFile` (:1656-1701) stages the file or calls `prefetchDragFile` (:1705), which GETs the whole object into memory.
- `keepForDragOut` (:1730) moves the pending file into the drag folder, named by `DragFileName`.

## 8. Naming

- `TemplateExpander` and `ObjectKeyNamer.makeKey(ext:)` already take the extension as a parameter.
- Hard-coded png elsewhere:
  - AppCoordinator :816, :829, :1034, :1039, :2058, :2230;
  - `Settings/UploadSettingsView.swift:62` (caption "The .png extension is added.") and :107 (`exampleKey ext "png"`);
  - `GeneralSettingsView:39` ("The PNG is kept inside TidyShot…");
  - `EditorNaming.swift:25` (`+".png"`) and :36 (`.png` only);
  - `DragFileName.swift:19`;
  - `FileNamer.defaultTemplate` "Screenshot {date} at {time}".

## 9. Status menu and capture lock (scrolling capture is the template)

- `withCaptureLock(coversDesktop:)` (AppCoordinator :2427-2438) uses `isCapturing` as a guard and resets it with a `defer`.
- `isCapturing` is read by `StatusMenuController:119` (disables the capture items) and `URLCommandHandler:118` (drops capture commands).
- The status icon observes only `isUploading` (`StatusMenuController:41-51`).
- Scrolling session:
  - Shortcut re-entry before the lock: `if scrollCapture.isRunning { advance(); return }` (:300-303).
  - The lock is held for the whole session (`withCaptureLock(coversDesktop: false)` :304; `runScrolling` :335-358 ends in `save`).
  - The Escape hotkey `.cancelCapture` (`App/Shortcuts.swift:20`) is enabled only while a session or countdown runs. Its handler (:217-221) cancels the self-timer and the scroll capture.
- `ScrollCaptureController.run` (:35-81):
  - frame window (`ScrollAreaFrameWindow`, click-through, dashed);
  - `ScrollCapturePanel`: non-activating borderless `NSPanel`, floating, on all Spaces, can become key;
  - placement by `ScrollPanelGeometry` (right of the area, else left, else inside);
  - awaits a continuation;
  - `close` disables Escape.
- `ScrollFrameSource.makeFilter` (:124-136) excludes TidyShot's whole application, or else its own windows by number (`OverlayWindowLookup`). Stream config: `sourceRect`, pixel size, 30 fps, `showsCursor = false`.
- URL commands: `URLCommand.Kind`, `URLCommandTarget`, handler dispatch. "Recording commands" are deferred in the spec.
- Shortcuts: `App/Shortcuts.swift`, `registerShortcuts` (AppCoordinator :186-222), `ShortcutsSettingsView` rows.
- Entitlements: no `device.audio-input`. Output goes to the container `tmp` and `pending`, or the user-selected save folder.
- `Capture/CaptureTarget.swift`: `.display`, `.area`, `.window`; `CaptureResult` is image-only.
