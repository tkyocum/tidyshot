import CoreGraphics

/// Posts scroll-wheel events for auto-scroll (spec 2.8, Auto-scroll driver). Positive `points`
/// move the content up, showing what lies below, as scrolling down does. Main actor by the module
/// default; the real poster is nonisolated, the tests' fake is a main-actor class.
protocol ScrollEventPoster {
    func post(points: CGFloat)
}

/// One continuous, pixel-unit wheel event at the HID tap. It goes to the window under the
/// pointer, so the driver posts only while the pointer is over the area. Without the PostEvent
/// grant macOS drops it silently.
nonisolated struct HIDScrollEventPoster: ScrollEventPoster {
    func post(points: CGFloat) {
        guard let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .pixel,
                                  wheelCount: 1, wheel1: Int32(-points.rounded()), wheel2: 0, wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }
}
