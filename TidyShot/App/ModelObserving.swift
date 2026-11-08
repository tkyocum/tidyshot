import Observation

/// Following an `@Observable` model from a main-actor object, as every observer in the app does:
/// `withObservationTracking` reports one change per registration, before it happens, so `read` is
/// registered again and `apply` runs with the new value on the next main-actor turn
/// (`StatusMenuController.updateIcon` is the pattern written out). `self` is held weakly between
/// turns, so the chain ends with the object. Main-actor classes are Sendable, so any of them conforms.
protocol ModelObserving: AnyObject, Sendable {}

extension ModelObserving {
    func follow<Value>(_ read: @escaping @MainActor (Self) -> Value, apply: @escaping @MainActor (Self, Value) -> Void) {
        let value = withObservationTracking { read(self) } onChange: { [weak self] in
            Task { @MainActor in self?.follow(read, apply: apply) }
        }
        apply(self, value)
    }
}
