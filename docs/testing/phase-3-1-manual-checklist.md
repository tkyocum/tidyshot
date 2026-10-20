# Phase 3.1 manual test checklist

Run after any change to the menu bar item, Recent Captures, Delete, Copy Image, the Upload tab or
the selection overlay. Automated tests cover the template migration, the luminance sampling, the
signed GET, the alert texts, the row text and the preview placement; everything here needs a
real menu bar, a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, after-capture action "Upload and copy URL", at least three captures in
history: one uploaded, one saved without upload ("Save and copy image"), one upload-only, and one
made before this build. Where the Phase 2 and Phase 3 checklists say Recent Captures shows
`Saved` or `Failed`, the submenu row shows no suffix or "· Upload failed".

## Menu bar
- [ ] One TidyShot icon (the viewfinder), no Dock icon. Opening the menu leaves the frontmost app active: its name stays in the menu bar.
- [ ] Items in order: Capture Area `⌃⇧4`, Capture Window `⌃⇧2`, Capture Fullscreen `⌃⇧3`, Recent Captures (with a chevron), Retry Failed Uploads (only with a failed upload), Reveal Last Capture, Settings… `⌘,`, Quit TidyShot `⌘Q`.
- [ ] Change the area shortcut in Settings > Shortcuts, reopen the menu: the title shows the new shortcut. Put it back.
- [ ] Each capture item starts its capture. Reveal Last Capture is disabled before the first save in this launch, then reveals the file.
- [ ] Settings… opens the Settings window in front of the frontmost app, again after closing it, and from `⌘,` while the menu is open.
- [ ] Command-drag the icon to another place in the menu bar, quit and relaunch: it comes back where you put it.
- [ ] Network Link Conditioner (or a large fullscreen capture): during the upload the icon is `arrow.up.circle`, also while the menu is open, and returns to the viewfinder afterwards.
- [ ] With a failed upload in history, Retry Failed Uploads retries it and disappears from the menu once nothing has failed.
- [ ] Revoke Screen Recording and relaunch: the first item is "Screen Recording permission needed…" and opens the permission window.

## Recent Captures
- [ ] Hovering Recent Captures opens the submenu without a click; it lists the newest captures first, never more than 15 (take a 16th: the oldest row drops off).
- [ ] Each row shows a thumbnail, the object name (`aSIS7x.png`) or the file name, and the time: "now", "2 minutes ago", "yesterday"; an upload in flight adds "· Uploading", a failed one "· Upload failed". A capture made before Phase 3 gets its thumbnail on first display.
- [ ] The row under the mouse is highlighted; the menu highlight never sticks to a row the mouse has left.
- [ ] With VoiceOver on (`⌘F5`), moving through the submenu reads each row's name and time, with "Uploading" or "Upload failed" when shown, never a blank item. Keyboard navigation inside a row (reaching its buttons with the arrow keys or Tab) is out of scope for Phase 3.1; do not fail the checklist on it.
- [ ] Clicking an uploaded row closes the menu and puts the URL on the clipboard; clicking a never-uploaded row puts the file there (paste in Finder makes a copy).
- [ ] The link button is greyed out on a never-uploaded row; on an uploaded row it closes the menu and copies the URL.
- [ ] The photo button on a saved capture closes the menu, posts "Image copied", and Notes pastes the image at point size, not double.
- [ ] The photo button on an upload-only capture (no local file) posts "Copying image…", then "Image copied", and the paste works; with Wi-Fi off it posts "Could not copy image" with the reason.
- [ ] The photo button is greyed out on a capture made before Phase 3 whose file was deleted from the save folder.
- [ ] Rename the file of a capture that was saved but never uploaded (in Finder, in the save folder), then press its photo button: "Could not copy image" with "The local file could not be read." Rename it back.
- [ ] The trash button closes the menu and shows the delete alert (see Delete); after Delete the row is gone the next time the menu opens.
- [ ] With an empty history the submenu shows a greyed "No captures yet".

## Preview
- [ ] Moving onto a thumbnail shows the capture in a rounded panel above the menu, level with the row, at most 560 by 420 points, on the side of the submenu away from the status menu (on its right when it opened to the right of the menu); the menu stays open and the frontmost app stays active.
- [ ] Moving to the next thumbnail moves the panel to that row with that capture; moving onto a name or a button hides it; Escape, a click outside, or any row action hides it with the menu.
- [ ] An upload-only capture previews at thumbnail size (it has no local file to decode).
- [ ] Command-drag the icon to the right end of the menu bar: the submenu opens to the left of the menu and the panel is on the submenu's left. When the preferred side has no room (a submenu at a display's edge, or a narrow display) the panel opens on the other side and stays on screen.

## Delete
- [ ] Uploaded capture, from the trash button or the overlay: "Delete this capture?", "Removes it from object storage and from history.", Delete (red) and Cancel. Escape cancels. Delete removes the row, the object (`curl -I <url>` gives 403 or 404), the file in the save folder and the thumbnail.
- [ ] Saved capture never uploaded: the line reads "Removes it from your save folder and from history."; a capture uploaded before Phase 3: "Removes it from your save folder and from history. The uploaded object stays in the bucket."
- [ ] Wi-Fi off, Delete on an uploaded capture: a second alert, "Couldn't delete it from storage: …" with "Remove it from history anyway? The object stays in the bucket." and Remove (red) and Cancel. Cancel keeps the capture. Delete again, Remove: the row and thumbnail go, the file in the save folder stays, and with Wi-Fi back on `curl -I <url>` still gives 200.
- [ ] The same with an upload-only capture that has failed and is still in `pending/`: after Remove, its `pending/<UUID>.png` is gone.
- [ ] Forget Credentials, then Delete on an uploaded capture: the second alert says "Couldn't delete it from storage: No credentials are saved in Settings > Upload." Re-enter the credentials.
- [ ] Network Link Conditioner at 100% loss, Delete on an uploaded capture, then the trash button in the overlay and in the submenu for the same capture while the request hangs: no second alert appears.

## Templates and Upload tab
- [ ] Before installing this build, with the Phase 3 build, set the file name template to `{app} {datetime}` and the key template to `shots/{app}/{random:8}` and save. After launching this build: Settings > General shows `{datetime}`, Settings > Upload shows `shots/{random:8}`, and `defaults read ~/Library/Containers/io.tky.tidyshot/Data/Library/Preferences/io.tky.tidyshot.plist` shows neither template with the old token. A capture uploads to `shots/XXXXXXXX.png`.
- [ ] Again with the Phase 3 build, set the file name template to `{app}` alone. After launching this build Settings > General shows the default template, and `log show --last 5m --predicate 'process == "TidyShot"' | grep "Naming template"` shows one line with the old template; quitting and relaunching adds no second line. No notification is posted.
- [ ] The token captions in Settings > General and Settings > Upload list `{date} {year} {month} {day} {time} {datetime} {hostname} {counter} {random} {random:8}`.
- [ ] An empty Endpoint and Public URL each show a grey "Required"; the example sits on its own caption line under each field.
- [ ] Both example captions are grey like the other captions, URL included (not a blue link), and clicking one opens nothing.
- [ ] Save and Test Connection with correct settings reports exactly "Upload and public read both work." with no URL after it; a wrong secret still reports "Upload failed: …".
- [ ] The Settings window is 600 by 800 points and fits on the screen with its toolbar. With the key template's orange warning showing, the Upload tab scrolls, and scrolling reaches everything down to the Save buttons and the status line under them.

## Crosshair
- [ ] `⌃⇧4` over a white window: after the first moment (white crosshair with a thin dark edge) the crosshair is black; over a dark window it is white; moving between them switches it.
- [ ] Dragging a rectangle across light and dark areas: its border takes the colour for the area under the cursor.
- [ ] Two displays with different backgrounds: each overlay picks the colour from its own display.
