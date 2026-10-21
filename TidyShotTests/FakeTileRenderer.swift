import CoreGraphics
import Foundation
import Synchronization
@testable import TidyShot

/// A `TileRendering` for the tile-cache and editor-model tests. It records each call as the key
/// it was asked for (the effect and the effects of the tiles passed beneath it) and returns a new
/// 1x1 image, so `===` tells a reused tile from a re-rendered one.
///
/// `tile` is `@concurrent`, so it runs off the main actor like the real actor does. With a
/// `gate`, the first call waits until the gate opens; later calls return at once. A call for an
/// effect whose id is in `failing` is recorded and returns nil, like a failed `createCGImage`,
/// until `recover(_:)` removes the id.
nonisolated final class FakeTileRenderer: TileRendering {
    let gate: TileGate?
    private let recorded = Mutex<[TileKey]>([])
    private let failing: Mutex<Set<UUID>>

    init(gate: TileGate? = nil, failing: Set<UUID> = []) {
        self.gate = gate
        self.failing = Mutex(failing)
    }

    /// Stops failing renders of the effect with `id`.
    func recover(_ id: UUID) {
        failing.withLock { _ = $0.remove(id) }
    }

    /// Every call so far, in the order they started.
    var calls: [TileKey] {
        recorded.withLock { $0 }
    }

    @concurrent func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage? {
        let isFirst = recorded.withLock { calls in
            calls.append(TileKey(effect: effect, beneath: beneath.map(\.effect)))
            return calls.count == 1
        }
        if isFirst, let gate {
            await gate.wait()
        }
        if failing.withLock({ $0.contains(effect.id) }) { return nil }
        return Self.pixel()
    }

    private static func pixel() -> CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}

/// Holds a render until the test calls `open()`. It suspends on a continuation and never blocks
/// a thread: a `DispatchSemaphore` here would block the main actor the tests run on.
actor TileGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}
