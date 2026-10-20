# Phase 3 manual test checklist

Phase 3.1 replaced the gallery window with the Recent Captures submenu and the three-button delete
alert with a two-button one. Skip the Gallery section and the "Remove from History Only" items
below; `docs/testing/phase-3-1-manual-checklist.md` covers them now.

Run after any change to Gallery, Overlay, History, Upload naming, or AppCoordinator. Automated
tests cover the template engine, key validation and migration, thumbnails and the two stores,
record migration, queue cancellation, deletion bookkeeping and the thumbnail provider; everything
here needs a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, after-capture action "Upload and copy URL", three or more captures in
history including at least one Phase 2 capture (made before this build).

## Gallery
- [ ] The menu shows "Recent Captures…" and no submenu; with an empty history the window shows "No captures yet".
- [ ] The grid lists captures newest first with a thumbnail and a status capsule each; Phase 2 captures whose files exist get thumbnails on first display (`thumbnails/` gains files, `history.json` gains `thumbnailFileName`); a Phase 2 capture whose file was deleted shows the placeholder icon, and scrolling past it again does not make the gallery try again (no new `thumbnails/` file, no stutter).
- [ ] Hovering a cell highlights it and the right-hand pane shows it larger with date, `W × H px`, app, URL or status, and file path.
- [ ] Clicking an Uploaded cell copies the URL (paste into Notes); clicking a Saved cell copies the file (paste in Finder makes a copy).
- [ ] Context menu offers Copy URL or Copy File, Retry Upload (Failed only), Reveal in Finder (local file only), Delete….
- [ ] Delete… on an uploaded capture: one alert, whose text names the object URL and the file, with the buttons "Delete", "Remove from History Only" and "Cancel"; Cancel changes nothing; Delete removes the row, `curl -I <url>` gives 403 or 404, the file is gone from the save folder, the thumbnail is gone from `thumbnails/`, and the preview pane no longer shows it.
- [ ] Delete… on a Phase 2 capture that was uploaded: the alert says the uploaded object stays in the bucket; Delete removes the row and the file, and `curl -I <url>` still gives 200.
- [ ] Delete… while offline on an uploaded capture: notification "Not deleted" and the row stays; back online, Delete… works.
- [ ] Network Link Conditioner at 100% packet loss, Delete… on an uploaded capture, choose Delete, then choose Delete… on the same capture again (gallery) and click its trash button (overlay) while the request hangs: no second alert appears.
- [ ] Forget Credentials, then Delete… on an uploaded capture: notification "Not deleted" telling you to save credentials or choose Remove from History Only, and the row stays; Delete… again and choose "Remove from History Only": the row and thumbnail go, the object (`curl -I <url>` gives 200) and the file in the save folder stay. Re-enter the credentials.
- [ ] Make the local file undeletable (`chflags uchg <file>` on a Saved capture), Delete…: notification "Not deleted" naming the file and the reason, and the row stays; `chflags nouchg <file>`, Delete… works.
- [ ] Change the Upload tab's bucket (to a second bucket you can write to) and Save, then Delete… a capture uploaded before the change: the object is removed from the bucket it was uploaded to (`curl -I <old url>` gives 403 or 404), not looked for in the new one.
- [ ] Key template `shared/{date}` and a key that cannot read objects (HEAD answers 403 for existing keys), two captures the same day: both rows point at the same key; Delete… the first: notification "Not deleted from storage" saying another capture shares this key, the row goes, and the second capture's URL still works.
- [ ] Retry Upload on a Failed capture with the network restored turns the capsule Uploaded and copies the URL.
- [ ] The window remembers its size and position across close and reopen; Escape and ⌘W close it.
- [ ] With the window open, a new capture appears at the top with its thumbnail and its capsule goes Uploading, then Uploaded.

## Overlay delete
- [ ] Trash button during an upload (fullscreen capture or Network Link Conditioner): the alert names "the upload in progress"; after Delete the overlay closes, the menu bar icon returns to the viewfinder, no object is in the bucket (list it, or GET the URL the overlay would have shown), no row, no file, no thumbnail.
- [ ] Trash button during an upload, right after saving the Upload tab (so the upload runs on the replaced queue): the upload is still cancelled, and the menu bar icon returns to the viewfinder.
- [ ] Trash button after the upload finished: object, row, file and thumbnail gone.
- [ ] Cancel in the alert keeps everything and the overlay stays.
- [ ] Clicking the thumbnail of an upload-only capture does nothing (no Finder reveal).

## Upload only
- [ ] Settings > General, "Upload only, keep no local file": the caption appears; with no save folder chosen, a capture shows no folder prompt, the overlay goes to "URL copied", pasting gives the URL, `pending/` is empty afterwards, the gallery row shows "No local file" and no Reveal item, "Reveal Last Capture" is disabled.
- [ ] Wi-Fi off, capture: overlay "Upload failed" with Retry, `pending/<UUID>.png` exists; Wi-Fi on, Retry from the gallery: Uploaded, and the pending file is gone.
- [ ] Wi-Fi off, capture in upload-only, then set retention to 1 day and wait past it (or change the record's `timestamp` in `history.json` to two days ago before relaunching) and take another capture: the failed upload-only row and its `pending/` file are still there.
- [ ] Forget Credentials, then capture in upload-only: one "Upload not configured" notification, the image is on the clipboard, the row is Failed and the pending file stays; re-enter credentials, Retry Upload: Uploaded.
- [ ] "Also copy image" on: paste gives the image until the upload finishes, then the URL.

## Key templates
- [ ] After updating from Phase 2 with prefix `shots` and length 8 saved, Settings > Upload shows `shots/{random:8}`; after Save, `defaults read ~/Library/Containers/io.tky.tidyshot/Data/Library/Preferences/io.tky.tidyshot.plist s3DestinationConfig` contains `keyTemplate` and no `keyPrefix` or `keyLength`.
- [ ] Template `shots/{year}/{month}/{hostname}-{random:8}`: the example updates as you type; Save; capture: the URL is `https://snap.tky.io/shots/2026/10/<hostname>-XXXXXXXX.png` with the hostname lowercased, without `.local`, and only `a-z`, `0-9`, `.` and `-` in it (an `_` in the Mac's host name shows as `-`).
- [ ] Template `{date}/{hostname}`: the orange warning appears and says the template has no {random} or {counter}, so captures can produce the same key and only the HEAD check keeps a capture from overwriting an earlier object; Save works; two captures on the same day: the second fails with "Could not find an unused object key after 5 tries." and keeps its file for retry.
- [ ] Settings > Upload with the warning showing: the tab is taller than the 800-point window and scrolls, and scrolling reaches everything down to the Save buttons.
- [ ] Template `my shots/{random}`: red message `" " is not allowed…`; Save shows "Key template: …" and does not save. Template `{foo}`: red `{foo} is not a token.`
- [ ] Save and Test Connection with a folder template: the status line's probe URL is inside that folder and the probe is gone afterwards.
- [ ] File name template `{year}-{month}-{day} {hostname}` names local files as expected; the default template still gives `Screenshot 2026-10-19 at 11.56.03.png`.
- [ ] A retried failed upload lands under the capture's own date folder, not today's; with `{counter}` in the key template, the retry's key has a newly drawn counter value, and an upload-only capture taken before a destination existed gets a real counter (not 0) when it is retried.

## Forget credentials
- [ ] Forget Credentials: the three fields clear, the status reads "Credentials removed from the keychain…", Keychain Access no longer has "TidyShot S3 credentials"; a capture gives "Upload not configured"; re-enter and Save: uploads work again.
- [ ] Forget Credentials while an upload is running: that upload still finishes (Uploaded, URL copied) and the menu bar icon returns to the viewfinder.

## History hygiene
- [ ] Retention 1 day with older captures present, then capture: older rows disappear, their files in `thumbnails/` are gone, and their files in the save folder remain; a failed upload-only capture is kept with its `pending/` file however old it is.
- [ ] Quit, replace `history.json` with `not json`, relaunch: the gallery is empty, `thumbnails/` and `pending/` are untouched, and `history.json.corrupt-<number>` exists.
