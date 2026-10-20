import AppKit
import SwiftUI

/// One Recent Captures menu item: the SwiftUI `RecentCaptureRow` in an `NSHostingView`, plus an
/// AppKit tracking area over the row for its highlight (a menu does not highlight custom views).
/// Tracking areas in a menu item's view receive `mouseEntered` and `mouseExited` while the menu
/// tracks; they never take clicks, which go to the row's buttons.
final class RecentCaptureMenuItemView: NSView {
    let recordID: UUID
    private let state = RecentCaptureRowState()
    private var rowArea: NSTrackingArea?

    init(record: CaptureRecord, now: Date, provider: ThumbnailProvider, actions: RecentCaptureActions) {
        recordID = record.id
        super.init(frame: CGRect(origin: .zero, size: RecentCaptureRow.size))
        let name = RecentCaptureFormatting.name(for: record)
        let detail = RecentCaptureFormatting.detail(for: record, now: now)
        let row = RecentCaptureRow(record: record, name: name, detail: detail,
                                   canCopyLink: RecentCaptureFormatting.canCopyLink(record),
                                   canCopyImage: RecentCaptureFormatting.canCopyImage(record),
                                   state: state, provider: provider, actions: actions)
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
        if let rowArea { removeTrackingArea(rowArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        rowArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        state.isHighlighted = true
    }

    override func mouseExited(with event: NSEvent) {
        state.isHighlighted = false
    }
}
