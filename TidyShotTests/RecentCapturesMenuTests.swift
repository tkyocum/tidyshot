import AppKit
import Testing
@testable import TidyShot

/// The Recent Captures submenu (`RecentCapturesMenu`) over a built coordinator. The menu is built and never
/// opened; its preview panel is made deferred and only hidden.
@Suite(.timeLimit(.minutes(1)))
struct RecentCapturesMenuTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
    }

    /// phase-3-1 :37. With an empty history the submenu shows one greyed `No captures yet`.
    @Test func anEmptyHistoryShowsOneDisabledNoCapturesYet() {
        defer { world.removeAll() }
        let menu = RecentCapturesMenu(coordinator: world.makeCoordinator(), closeMenus: {}, statusItemFrame: { nil })

        menu.rebuild()

        #expect(menu.menu.items.map(\.title) == ["No captures yet"])
        #expect(menu.menu.items.first?.isEnabled == false)
    }
}
