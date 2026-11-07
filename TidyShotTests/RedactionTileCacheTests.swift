import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The cache runs on the main actor, like these tests; the fake renderer runs off it.
struct RedactionTileCacheTests {
    let size = CGSize(width: 100, height: 100)
    let base: CGImage

    init() {
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        base = context.makeImage()!
    }

    func makeCache(_ renderer: FakeTileRenderer) -> RedactionTileCache {
        RedactionTileCache(base: base, renderer: renderer)
    }

    func redact(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Annotation {
        .redact(Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height)), fill: EditorPalette.defaultRedact)
    }

    func blur(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat = 2) -> Annotation {
        .blur(Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height)), radius: radius)
    }

    func pixelate(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, block: CGFloat = 4) -> Annotation {
        .pixelate(Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height)), block: block)
    }

    func document(_ annotations: Annotation...) -> AnnotationDocument {
        AnnotationDocument(annotations: annotations)
    }

    /// A blur reads `ceil(3 * radius)` px around its rect, a pixelate its block-snapped rect and a
    /// redact only its own rect. Rects that only touch along an edge share no pixel. A later
    /// effect also inherits what lies beneath the tiles it samples.
    @Test func keysIncludeOnlySampledEarlierEffects() {
        let secret = redact(10, 10, 20, 20)             // x 10..<30
        let touching = redact(30, 10, 5, 5)             // starts where `secret` ends
        let blurred = blur(35, 10, 20, 20, radius: 2)   // samples x 29..<61, y 4..<36
        let far = redact(70, 70, 10, 10)
        let mosaic = pixelate(36, 28, 8, 8, block: 4)   // meets `blurred` (y 28..<30) and nothing else
        let keys = RedactionTileCache.keys(for: [secret, touching, blurred, far, mosaic], imageSize: size)

        #expect(keys.count == 5)
        #expect(keys[secret.id] == TileKey(effect: secret, beneath: []))
        #expect(keys[touching.id] == TileKey(effect: touching, beneath: []))
        #expect(keys[blurred.id] == TileKey(effect: blurred, beneath: [secret, touching]))
        #expect(keys[far.id] == TileKey(effect: far, beneath: []))
        #expect(keys[mosaic.id] == TileKey(effect: mosaic, beneath: [secret, touching, blurred]))

        // The blur radius sets the margin: 2 px reads from x 11, 3 px from x 8.
        let left = redact(0, 50, 10, 10)
        let narrow = blur(17, 50, 10, 10, radius: 2)
        let wide = blur(17, 50, 10, 10, radius: 3)
        #expect(RedactionTileCache.keys(for: [left, narrow], imageSize: size)[narrow.id]?.beneath == [])
        #expect(RedactionTileCache.keys(for: [left, wide], imageSize: size)[wide.id]?.beneath == [left])
    }

    @Test func unchangedEffectIsNotRerendered() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        var changes = 0
        cache.onChange = { changes += 1 }
        let secret = redact(10, 10, 20, 20)
        let start = document(secret)
        cache.reconcile(document: start, transient: nil)
        await cache.renderTask?.value
        let tile = try #require(cache.currentTile(for: secret.id))
        #expect(renderer.calls == [TileKey(effect: secret, beneath: [])])
        #expect(changes == 1)

        // A drawing, a transient drawing and an effect far away leave the tile alone.
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 0, y: 0, width: 50, height: 50),
                                                color: EditorPalette.defaultStroke, lineWidth: 8))
        let dragging = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 5, y: 5, width: 30, height: 30),
                                                     color: EditorPalette.defaultStroke, lineWidth: 8))
        let far = redact(70, 70, 10, 10)
        let more = start.appending(box).appending(far)
        cache.reconcile(document: more, transient: dragging)
        await cache.renderTask?.value

        #expect(renderer.calls.map(\.effect) == [secret, far])
        #expect(cache.currentTile(for: secret.id) === tile)
        #expect(changes == 2)
    }

    @Test func movingEarlierEffectRerendersOverlappingLater() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        let secret = redact(10, 10, 20, 20)
        let blurred = blur(25, 10, 20, 20, radius: 2)   // overlaps `secret`
        let mosaic = pixelate(36, 28, 8, 8, block: 4)   // overlaps `blurred` only
        let before = document(secret, blurred, mosaic)
        cache.reconcile(document: before, transient: nil)
        await cache.renderTask?.value
        let oldBlur = try #require(cache.tiles[blurred.id]?.image)
        let oldMosaic = try #require(cache.tiles[mosaic.id]?.image)

        let moved = secret.moved(by: CGVector(dx: 2, dy: 0))
        let after = before.replacing(moved)
        cache.reconcile(document: after, transient: nil)
        // Until the new tiles land, the old ones are pending, never shown.
        #expect(cache.currentTile(for: blurred.id) == nil)
        await cache.renderTask?.value

        // All three re-render in creation order, each over the new tiles beneath it.
        #expect(Array(renderer.calls.dropFirst(3)) == [TileKey(effect: moved, beneath: []),
                                                         TileKey(effect: blurred, beneath: [moved]),
                                                         TileKey(effect: mosaic, beneath: [blurred])])
        #expect(cache.tiles[mosaic.id]?.key == TileKey(effect: mosaic, beneath: [moved, blurred]))
        #expect(try #require(cache.currentTile(for: blurred.id)) !== oldBlur)
        #expect(try #require(cache.currentTile(for: mosaic.id)) !== oldMosaic)
    }

    @Test func nonOverlappingLaterKeepsTile() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        let secret = redact(10, 10, 20, 20)
        let blurred = blur(60, 60, 20, 20, radius: 2)   // samples x and y 54..<86
        let before = document(secret, blurred)
        cache.reconcile(document: before, transient: nil)
        await cache.renderTask?.value
        let kept = try #require(cache.tiles[blurred.id]?.image)

        let moved = secret.moved(by: CGVector(dx: 20, dy: 20))   // x and y 30..<50
        let after = before.replacing(moved)
        cache.reconcile(document: after, transient: nil)
        await cache.renderTask?.value

        #expect(renderer.calls.dropFirst(2).map(\.effect) == [moved])
        #expect(cache.currentTile(for: blurred.id) === kept)
    }

    /// The first render is held at the gate while a second reconcile moves the blur. The second
    /// pass stores its tile; then the held result arrives and must not replace it.
    @Test func staleReconcileResultDropped() async throws {
        let gate = TileGate()
        let renderer = FakeTileRenderer(gate: gate)
        let cache = makeCache(renderer)
        let first = blur(10, 10, 20, 20)
        let second = first.moved(by: CGVector(dx: 8, dy: 0))
        cache.reconcile(document: document(first), transient: nil)
        let held = try #require(cache.renderTask)
        try await eventually { renderer.calls.count == 1 }

        cache.reconcile(document: document(second), transient: nil)
        await cache.renderTask?.value
        let latest = try #require(cache.currentTile(for: second.id))

        await gate.open()
        await held.value
        #expect(cache.tiles[second.id]?.key == TileKey(effect: second, beneath: []))
        #expect(cache.currentTile(for: second.id) === latest)
        #expect(renderer.calls.map(\.effect) == [first, second])
    }

    /// The drag's tiles are still rendering (held at the gate) when mouseUp commits the same
    /// value, so the pass in flight finishes and nothing renders twice. The new effect is tiled
    /// last; an existing effect being moved keeps its place.
    @Test func transientTileCarriesOverOnCommit() async throws {
        let gate = TileGate()
        let renderer = FakeTileRenderer(gate: gate)
        let cache = makeCache(renderer)
        let secret = redact(10, 10, 20, 20)
        let start = document(secret)
        let dragged = blur(20, 20, 30, 30)   // a new blur being dragged over the redaction
        #expect(RedactionTileCache.orderedEffects(in: start, transient: dragged) == [secret, dragged])
        cache.reconcile(document: start, transient: dragged)
        let pass = try #require(cache.renderTask)
        try await eventually { renderer.calls.count == 1 }

        // The commit, with the transient still set and then cleared, wants the same keys.
        let committed = start.appending(dragged)
        cache.reconcile(document: committed, transient: dragged)
        cache.reconcile(document: committed, transient: nil)
        await gate.open()
        await pass.value
        #expect(renderer.calls == [TileKey(effect: secret, beneath: []), TileKey(effect: dragged, beneath: [secret])])
        let tile = try #require(cache.currentTile(for: dragged.id))

        let nudged = secret.moved(by: CGVector(dx: 1, dy: 0))
        #expect(RedactionTileCache.orderedEffects(in: committed, transient: nudged) == [nudged, dragged])
        cache.reconcile(document: committed, transient: nudged)
        await cache.renderTask?.value
        #expect(renderer.calls.dropFirst(2).map(\.effect) == [nudged, dragged])
        #expect(cache.currentTile(for: dragged.id) !== tile)
        let movedTile = try #require(cache.currentTile(for: nudged.id))
        let moveCommitted = committed.replacing(nudged)
        cache.reconcile(document: moveCommitted, transient: nil)
        await cache.renderTask?.value
        #expect(renderer.calls.count == 4)
        #expect(cache.currentTile(for: nudged.id) === movedTile)
    }

    @Test func allTilesRendersMissingInOrder() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        let secret = redact(10, 10, 20, 20)
        let far = redact(70, 70, 10, 10)
        let start = document(secret, far)
        cache.reconcile(document: start, transient: nil)
        await cache.renderTask?.value
        let secretTile = try #require(cache.tiles[secret.id]?.image)
        let farTile = try #require(cache.tiles[far.id]?.image)

        // Two effects the preview has not rendered, the second over the first.
        let mosaic = pixelate(40, 10, 16, 16, block: 4)
        let blurred = blur(50, 10, 20, 20, radius: 2)   // samples x 44..<76, so it reads `mosaic`
        let export = start.appending(mosaic).appending(blurred)
        let tiles = await cache.allTiles(for: export)

        #expect(tiles.map(\.effect) == [secret, far, mosaic, blurred])
        #expect(tiles[0].image === secretTile)
        #expect(tiles[1].image === farTile)
        #expect(Array(renderer.calls.dropFirst(2)) == [TileKey(effect: mosaic, beneath: []),
                                                         TileKey(effect: blurred, beneath: [mosaic])])
        // Export renders leave the preview's tiles to `reconcile`.
        #expect(cache.tiles[mosaic.id] == nil)
    }

    @Test func removedEffectDropsTile() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        var changes = 0
        cache.onChange = { changes += 1 }
        let secret = redact(10, 10, 20, 20)
        let far = redact(70, 70, 10, 10)
        let dragged = blur(40, 40, 10, 10)               // samples 34..<56, clear of both
        let both = document(secret, far)
        cache.reconcile(document: both, transient: dragged)
        await cache.renderTask?.value
        #expect(cache.tiles.count == 3)
        #expect(changes == 3)

        // Deleting `secret` drops its tile at once; nothing else renders.
        let rest = both.removing(id: secret.id)
        cache.reconcile(document: rest, transient: dragged)
        #expect(cache.tiles[secret.id] == nil)
        #expect(cache.renderTask == nil)
        #expect(changes == 4)

        // Abandoning the drag drops the transient tile too.
        cache.reconcile(document: rest, transient: nil)
        #expect(Set(cache.tiles.keys) == [far.id])
        #expect(renderer.calls.count == 3)
        #expect(changes == 5)
    }

    /// A redact whose render fails must never let a later blur or pixelate render over the raw
    /// pixels it should cover, in the preview or in the export.
    @Test func failedBeneathTileLeavesLaterPending() async throws {
        let secret = redact(10, 10, 20, 20)
        let blurred = blur(25, 10, 20, 20, radius: 2)   // samples the redact's pixels
        let far = redact(70, 70, 10, 10)
        let renderer = FakeTileRenderer(failing: [secret.id])
        let cache = makeCache(renderer)
        let start = document(secret, blurred)
        cache.reconcile(document: start, transient: nil)
        await cache.renderTask?.value

        // The pass ended at the failed redact: nothing was rendered over it, nothing is shown.
        #expect(cache.tiles[secret.id] == nil)
        #expect(cache.tiles[blurred.id] == nil)
        #expect(cache.currentTile(for: blurred.id) == nil)
        #expect(renderer.calls.map(\.effect) == [secret])

        // The export leaves the blur out too, and never renders it without the redact beneath.
        let exported = await cache.allTiles(for: start)
        #expect(exported.isEmpty)
        #expect(renderer.calls.allSatisfy { $0.effect.id == secret.id })

        // A later reconcile that changes the keys renders the redact again, then the blur over it.
        renderer.recover(secret.id)
        let later = start.appending(far)
        cache.reconcile(document: later, transient: nil)
        await cache.renderTask?.value
        #expect(renderer.calls.contains(TileKey(effect: blurred, beneath: [secret])))
        #expect(cache.tiles[blurred.id]?.key == TileKey(effect: blurred, beneath: [secret]))
        #expect(cache.currentTile(for: blurred.id) != nil)
        #expect(await cache.allTiles(for: later).map(\.effect) == [secret, blurred, far])
    }

    /// A redact created after a blur lies under it all the same (spec 2.6): adding it changes the
    /// blur's key and re-renders the blur over it, and moving it out of reach or deleting it
    /// changes the key back.
    @Test func redactAddedAfterBlurChangesBlurKey() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        let blurred = blur(10, 10, 30, 30, radius: 2)   // samples x and y 4..<46
        let start = document(blurred)
        cache.reconcile(document: start, transient: nil)
        await cache.renderTask?.value
        let plain = try #require(cache.tiles[blurred.id]?.image)

        let secret = redact(42, 20, 10, 10)               // clear of the blur's rect, in its margin
        let later = start.appending(secret)
        #expect(RedactionTileCache.keys(for: later.effects, imageSize: size)[blurred.id]
            == TileKey(effect: blurred, beneath: [secret]))
        cache.reconcile(document: later, transient: nil)
        // Until the new tile lands, the stored one is stale and never shown.
        #expect(cache.currentTile(for: blurred.id) == nil)
        await cache.renderTask?.value

        // The redact renders first, then the blur over it.
        #expect(Array(renderer.calls.dropFirst()) == [TileKey(effect: secret, beneath: []),
                                                        TileKey(effect: blurred, beneath: [secret])])
        #expect(try #require(cache.currentTile(for: blurred.id)) !== plain)
        let moved = later.replacing(secret.moved(by: CGVector(dx: 10, dy: 0)))   // x 52..<62
        #expect(RedactionTileCache.keys(for: moved.effects, imageSize: size)[blurred.id]?.beneath == [])
        let deleted = later.removing(id: secret.id)
        #expect(RedactionTileCache.keys(for: deleted.effects, imageSize: size)[blurred.id]?.beneath == [])
    }
}
