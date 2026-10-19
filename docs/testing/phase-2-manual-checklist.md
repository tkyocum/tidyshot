# Phase 2 manual test checklist

Run after any change to Upload, History, Overlay, or AppCoordinator. Automated tests cover
signing (AWS test suite plus the S3 worked examples), URL building, key naming, the queue,
the keychain store, and history persistence; everything here needs a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a bucket you can
write to, its public URL base (for example `https://snap.tky.io/`), and an access key pair.

## Upload settings
- [ ] Settings > Upload: Save with an empty endpoint shows "Endpoint must be an http or https URL…" in red.
- [ ] Fill in endpoint, region, bucket, public URL `https://snap.tky.io/{key}`, access key ID and secret; Save shows "Saved."
- [ ] Quit and relaunch: the fields are filled in again, including the secret (read back from the keychain).
- [ ] Enter a session token, Save, quit and relaunch: the token field is filled in again; clear it and Save: after relaunch it stays empty.
- [ ] Paste a bucket name with a trailing space, Save: the field shows the trimmed name and uploads work.
- [ ] `defaults read io.tky.tidyshot` does not contain the access key ID or secret.
- [ ] Keychain Access (login keychain) shows an item "TidyShot S3 credentials" with account `default`.
- [ ] Save and Test Connection with correct settings reports "Upload and public read both work." and the probe object is gone from the bucket afterwards.
- [ ] Save and Test Connection with a key that may PUT but not DELETE reports the outcome plus "Probe object … could not be deleted; remove it by hand." in red.
- [ ] Save and Test Connection with a wrong secret reports "Upload failed: Server returned HTTP 403…".
- [ ] Save and Test Connection with a public URL template pointing at a domain that does not serve the bucket reports "Upload worked, but the public URL returned HTTP …".
- [ ] Random name length stepper stops at 4 and 32; the example key updates as the prefix and length change.

## Capture and upload (⌃⇧3, ⌃⇧4, ⌃⇧2)
- [ ] After-capture action "Upload and copy URL": capture, wait for the overlay checkmark, paste into Slack or Notes: a working `https://snap.tky.io/XXXXXX.png` link appears, nothing else.
- [ ] From releasing the mouse to a pasteable link takes about two seconds on a normal connection.
- [ ] The menu bar icon shows an up-arrow circle while uploading and returns to the viewfinder afterwards.
- [ ] Notification "Uploaded, URL copied" appears; clicking it opens the URL in the browser.
- [ ] The uploaded object is a PNG with 144 DPI on a Retina display (download it and check with Preview > Tools > Show Inspector).
- [ ] With "Also copy image" on: immediately after capture, paste gives the image; after the upload finishes, paste gives the URL.
- [ ] With "Send public-read ACL" on, uploads still succeed on a bucket that allows ACLs, and the object is public.
- [ ] After-capture action "Save and copy image": no upload happens, paste gives the image, Recent Captures shows the item as `Saved`.
- [ ] Delete the "TidyShot S3 credentials" item in Keychain Access, relaunch, leave the action on "Upload and copy URL", capture twice: one "Upload not configured" notification only, and paste gives the image both times. Settings > Upload then shows empty credential fields and no red keychain error.
- [ ] Set key prefix `shots`: new objects land under `shots/` and the URL is `https://snap.tky.io/shots/XXXXXX.png`.
- [ ] Path-style on against MinIO (`http://localhost:9000`, region `us-east-1`): upload succeeds.

## Overlay
- [ ] Panel appears in the chosen corner of the display under the mouse, 16 pt from the edges, without taking focus from the frontmost app.
- [ ] Progress ring moves during a large (fullscreen Retina) upload, then shows the checkmark and URL.
- [ ] "Copy URL" puts the URL on the clipboard again after something else was copied.
- [ ] Clicking the thumbnail reveals the file in Finder.
- [ ] Auto-close happens 5 s after the upload finishes; hovering keeps it open; moving away closes it a second later.
- [ ] Auto-close 0 keeps the panel until the X is clicked.
- [ ] Settings > Overlay off: no panel, uploads still work.
- [ ] A second capture replaces the panel with the new capture.

## Failures and history
- [ ] Turn Wi-Fi off, capture: the file is saved, the overlay shows "Upload failed" with Retry, a notification appears, Recent Captures shows the item as `Failed`, nothing is on the clipboard unless "Also copy image" is on.
- [ ] Turn Wi-Fi on, click Retry in the overlay: the upload succeeds and the URL is copied.
- [ ] Recent Captures > Retry Failed Uploads retries every `Failed` item.
- [ ] Choosing an `Uploaded` history item copies its URL; choosing a `Saved` item reveals the file.
- [ ] Recent Captures titles contain only words, times and file names, no emoji.
- [ ] Quit while an upload is in flight (slow connection or large capture), relaunch: the item shows as `Failed` (history.json has "Upload was interrupted.") and Retry works.
- [ ] Wrong secret: the overlay shows "Upload failed … HTTP 403" after one attempt, no retries in the log.
- [ ] `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/history.json` lists the captures newest first.
- [ ] Quit, replace history.json with the text `not json`, relaunch: Recent Captures is empty, and `history.json.corrupt-<number>` next to it still holds `not json` after the next capture.
- [ ] With captures older than a day in history, set retention to 1 day and take a capture without relaunching: the older items are gone from Recent Captures, their files are still on disk.
