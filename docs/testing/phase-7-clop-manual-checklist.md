# Phase 7 manual test checklist: Optimize images with Clop

Run after any change to `TidyShot/Upload/ClopClient.swift`, `TidyShot/Upload/ClopOptimiser.swift`,
`AppCoordinator.startUpload` and `cancelUpload`, the Images section of `UploadSettingsView`, or the
entitlements in `project.yml`. Automated tests cover the request and reply coding, the optimiser
against a fake transport (every skip reason, the work file's removal, the 144 DPI read) and the
setting's default and persistence. Nothing here runs without a real Clop, a real bucket and eyes, and
none of it has been run: all steps are for you.

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted, a working
destination saved in Settings > Upload, and Clop (direct or Setapp) installed and running, with PNG
conversion off in Clop's settings. Capture only made-up data: captures are uploaded and links may be
shared. The TidyShot log is
`log show --last 5m --predicate 'process == "TidyShot"' | grep "Clop:"`. Download an uploaded object
with `curl -sO <url>`; `sips -g dpiWidth -g pixelWidth <file>` reads its resolution and size. Note the
Clop version (Clop > About); the fixtures come from 3.6.2.

## Settings and build
- [ ] Settings > Upload ends with an `Images` section after `Object keys`: the toggle `Optimize images with Clop` (off by default) and the caption `Clop is an image optimizer that greatly reduces file size. Clop keeps its own copy of each image it optimizes.` With Clop installed there is no link.
- [ ] The toggle takes effect without Save: turn it on, close Settings with no Save, and `defaults read io.tky.tidyshot optimiseWithClop` reads `1`; the next upload is optimised. Turn it off again and the next upload is not.
- [ ] Clop not installed (move Clop out of Applications, or run on a Mac without it): the toggle is greyed, and `Get Clop` follows the caption and opens https://lowtechguys.com/clop. Quit and reopen Settings with Clop installed: the toggle is enabled again.
- [ ] `codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app` shows `app-sandbox`, `files.bookmarks.app-scope`, `files.user-selected.read-write`, `network.client` and `temporary-exception.mach-lookup.global-name` with exactly `com.lowtechguys.Clop.optimisationService` and `com.lowtechguys.Clop-setapp.optimisationService`, and no `get-task-allow`.

## Optimised uploads (Clop running, toggle on)
- [ ] An area capture uploads: the downloaded object is smaller than the saved file in the save folder (compare `ls -l`), is a PNG, and `sips -g dpiWidth` reads 144 on a 2x display. The saved file is unchanged and still full size.
- [ ] A scrolling capture uploads optimised (the object is smaller than the saved file). The 65,536 px capture of the Phase 5 checklist, retried from Recent Captures, uploads and the object opens in a browser.
- [ ] Editor Upload (same link), the same-key replace, Upload as New and Retry of a failed upload (turn the network off, capture, turn it on, Retry) are each optimised: each object is smaller than the file the editor saved or the capture was.
- [ ] Upload-only mode (After capture: `Upload only, keep no local file`): the object is optimised; while it uploads `pending/<id>.png` in the container is full size, and after a failed upload (network off) the kept file is still the captured size, not Clop's.
- [ ] No Clop floating result appears and the clipboard holds the URL, not an image. Clop's own history (its menu bar window) lists the images; that is its cache, as the caption says (`~/Library/Caches/Clop/backups/` holds a copy).
- [ ] A capture that Clop cannot shrink (upload a plain white fill, or the same optimised file twice) uploads the original with `Clop: the result is not smaller, uploading the original` in the log and no error notification.
- [ ] A key template with `{counter}`: three captures in a row get counters in the order the uploads started (`defaults read io.tky.tidyshot captureCounter` advanced by 3), even when the second is a large scrolling capture that Clop takes seconds over.

## Fallbacks
- [ ] Quit Clop, toggle on, capture: the original uploads, the log shows `Clop: Clop is not running, uploading the original`, no notification, and TidyShot does not launch Clop.
- [ ] Clop set to convert PNG to another format (Clop > Settings > Images): the original PNG uploads, with `Clop: Clop converted the image to another format, uploading the original`. Set it back.
- [ ] Free-tier Clop past its cap, if you can reach it: uploads still succeed, unoptimised, with a `Clop:` line.
- [ ] Quit Clop mid-optimisation: capture the 65,536 px scrolling capture (or retry it from Recent Captures) and quit Clop at once (Clop > Quit) while the card shows the upload at 0 %. The upload still finishes within about 30 seconds with the original bytes (the object is as big as the saved file), the log shows a `Clop:` line saying why, no error notification appears and the capture is not lost.

## Delete and settings changes during optimisation
- [ ] Delete while Clop is optimising a large scrolling capture: retry the 65,536 px capture from Recent Captures with Clop running, and choose Delete on its card during the first seconds, while it shows 0 %, then accept `Delete this capture?`. The capture leaves Recent Captures and nothing uploads afterwards (check the bucket after a minute: no new object for it).
- [ ] The same Delete where the record is kept: make the file removal fail (change the save folder in Settings > General so the capture's file lies outside it), start the retry, Delete during the first seconds, and decline the second alert. The card reads `Upload cancelled.`; Retry then uploads once, with one new object in the bucket, not two. Then Delete again and accept the second alert's Remove.
- [ ] With the file removal made to fail as above, Delete, decline the second alert, then Retry before Clop's first call returns (a 65,536 px capture gives you seconds): exactly one object is uploaded, and it comes from the second attempt (its key is the new one; the first attempt's bytes never reach the bucket).
- [ ] Change upload settings during optimisation: start the 65,536 px upload with Clop running, and in Settings > Upload change the bucket (or the key template) and Save while the card shows 0 %. The first upload completes against the destination it started with, and its URL is copied; a capture taken afterwards goes to the new destination. Nothing hangs and no job is dropped.
- [ ] Toggle the setting off while an optimisation runs: the running upload still completes optimised; the next one is not.
