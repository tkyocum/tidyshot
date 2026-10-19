# Phase 1 manual test checklist

Run after any change to Capture, Selection, or Output. Automated tests cover geometry, naming,
encoding, and window filtering; everything here needs eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, default settings.

## Permission
- [ ] Revoke Screen Recording in System Settings, relaunch: permission window appears, menu shows the permission item.
- [ ] Grant it: window turns green within a second; relaunch clears the window and menu item.

## Fullscreen (⌃⇧3)
- [ ] Captures the display under the cursor, at full pixel resolution, 144 DPI on Retina.
- [ ] Cursor absent by default; present when "Show cursor" is on.

## Area (⌃⇧4)
- [ ] Dim, crosshair, loupe appear on all displays, with Safari frontmost before the hotkey.
- [ ] Escape before any click cancels.
- [ ] Drag shows a clear rectangle, white border, "W × H" label; label flips above when near the bottom.
- [ ] Release saves `W*scale × H*scale` pixels with no dimming, crosshair, or loupe in the image.
- [ ] Click on the desktop cancels. Click on a window captures that window.
- [ ] Hotkey on display A, move to display B, drag there: capture comes from display B.
- [ ] Loupe at a screen corner shows black outside the screen and keeps the crosshair on the cursor pixel.
- [ ] Pressing the shortcut while the overlay is up does nothing extra.
- [ ] With no save folder set, the folder chooser appears above the screen, not under a dim overlay.

## Window (⌃⇧2)
- [ ] Hover highlights the frontmost window under the cursor; desktop gives no highlight.
- [ ] Two overlapping windows: the one in front is highlighted and captured.
- [ ] Click saves the window alone, no shadow, correct pixel size.
- [ ] Dragging draws nothing; release over a window captures it.
- [ ] `{app}` resolves to the window's app.
- [ ] Escape cancels.

## Output
- [ ] File lands in the chosen folder with the template name; same-second captures get " 2", also after a relaunch.
- [ ] Paste into Notes shows the image at point size, not double.
- [ ] Notification appears; clicking it reveals the file in Finder.
- [ ] Cancelling the folder chooser leaves the image on the clipboard and shows a "Not saved" notification.
- [ ] Shutter sound plays; toggles for sound, notification, and clipboard are honoured.
- [ ] Quit and relaunch: save folder remembered, counter continues.

## Settings
- [ ] Rebinding a shortcut takes effect immediately and shows in the menu.
- [ ] Choose… changes the folder and the next capture lands there.
