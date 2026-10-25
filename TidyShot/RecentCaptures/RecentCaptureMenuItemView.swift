import AppKit
import SwiftUI

/// One Recent Captures menu item: the SwiftUI `RecentCaptureRow` in an `NSHostingView`, plus two
/// AppKit tracking areas, one over the row for its highlight (a menu does not highlight custom
/// views) and one over the thumbnail for the preview. Tracking areas in a menu item's view
/// receive `mouseEntered` and `mouseExited` while the menu tracks; they never take clicks, which
/// go to the row's buttons.
final class RecentCaptureMenuItemView: NSView {
    let recordID: UUID
    private let state = RecentCaptureRowState()
    /// Called with true when the mouse enters the thumbnail and false when it leaves.
    private let onThumbnailHover: (RecentCaptureMenuItemView, Bool) -> Void
    private var rowArea: NSTrackingArea?
    private var thumbnailArea: NSTrackingArea?

    /// `saveFolder` and `retainedID` say what Annotate can load from, `isOptimizing` whether a
    /// recording waits for Clop, and `trimState` its Trim items; the menu reads them once per rebuild.
    init(record: CaptureRecord, now: Date, saveFolder: URL?, retainedID: UUID?, isOptimizing: Bool,
         trimState: RecordingTrim.MenuState, provider: ThumbnailProvider, actions: RecentCaptureActions,
         onThumbnailHover: @escaping (RecentCaptureMenuItemView, Bool) -> Void) {
        recordID = record.id
        self.onThumbnailHover = onThumbnailHover
        super.init(frame: CGRect(origin: .zero, size: RecentCaptureRow.size))
        let name = RecentCaptureFormatting.name(for: record)
        let detail = RecentCaptureFormatting.detail(for: record, now: now, isOptimizing: isOptimizing)
        let row = RecentCaptureRow(record: record, name: name, detail: detail,
                                   detailWithoutSize: RecentCaptureFormatting.detailWithoutSize(
                                       for: record, now: now, isOptimizing: isOptimizing),
                                   canCopyLink: RecentCaptureFormatting.canCopyLink(record),
                                   canCopyImage: RecentCaptureFormatting.canCopyImage(record),
                                   canAnnotate: RecentCaptureFormatting.canAnnotate(record, retainedID: retainedID,
                                                                                    saveFolder: saveFolder),
                                   showsImageActions: RecentCaptureFormatting.showsImageActions(record),
                                   canCopyFile: RecentCaptureFormatting.canCopyFile(record),
                                   clickOpens: RecentCaptureFormatting.rowClickOpens(record),
                                   trimState: trimState, state: state, provider: provider, actions: actions)
        let host = NSHostingView(rootView: row)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        // The menu item has no title, so without this VoiceOver reads a blank item.
        host.setAccessibilityLabel("\(name), \(detail)")
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateTrackingAreas() {
        for area in [rowArea, thumbnailArea].compactMap({ $0 }) {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let row = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        let thumbnail = NSTrackingArea(rect: RecentCaptureRow.thumbnailFrame, options: options, owner: self, userInfo: nil)
        addTrackingArea(row)
        addTrackingArea(thumbnail)
        rowArea = row
        thumbnailArea = thumbnail
        super.updateTrackingAreas()
    }

    /// A menu item's view gets no `mouseExited` when its submenu closes under the mouse, so the
    /// highlight is cleared whenever the view joins or leaves a window; the row never comes back
    /// highlighted when the submenu opens again.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        state.isHighlighted = false
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === thumbnailArea {
            onThumbnailHover(self, true)
        } else if event.trackingArea === rowArea {
            state.isHighlighted = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === thumbnailArea {
            onThumbnailHover(self, false)
        } else if event.trackingArea === rowArea {
            state.isHighlighted = false
        }
    }
}
