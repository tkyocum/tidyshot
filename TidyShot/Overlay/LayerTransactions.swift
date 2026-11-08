import QuartzCore

extension CATransaction {
    /// Runs `body` in a transaction with implicit animations off, so the layer changes land at
    /// once: the overlays' layers follow the pointer or the zoom, and a fade would be filmed.
    static func withoutActions<T>(_ body: () throws -> T) rethrows -> T {
        begin()
        setDisableActions(true)
        defer { commit() }
        return try body()
    }
}
