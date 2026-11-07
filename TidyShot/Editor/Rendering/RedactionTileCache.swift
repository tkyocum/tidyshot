import CoreGraphics
import Foundation

/// What a redaction tile was rendered from: the effect's own value and the values of the effects
/// whose pixels reach it, in creation order. Equal keys mean equal tile pixels, so a tile is
/// reused exactly when its key is unchanged.
nonisolated struct TileKey: Equatable, Sendable {
    let effect: Annotation
    let beneath: [Annotation]
}

/// The editor's preview tiles for redact, blur and pixelate, one per effect, rendered by a
/// `TileRendering` (the app's `RedactionRenderer`) off the main actor.
///
/// There is no invalidation pass. `reconcile(document:transient:)` computes the key every effect
/// wants now and renders the effects whose stored key differs. A change to an effect changes the
/// key of every blur and pixelate that samples it, so those re-render too. The renders of one call
/// run in one task, the redacts first and the rest in creation order, each over the tiles beneath
/// it, and a later call wins: every result is checked against the cache-wide generation before it
/// is stored.
final class RedactionTileCache {
    /// The newest tile for each effect id and the key it was rendered for. An entry whose key
    /// differs from the effect's current key is stale and is never shown; `currentTile` checks.
    private(set) var tiles: [UUID: (key: TileKey, image: CGImage)] = [:]
    /// Called on the main actor after a tile is stored or tiles are dropped.
    var onChange: () -> Void = {}
    /// The render pass for the keys of the latest `reconcile`, or nil when they needed no render.
    /// Awaiting it waits until those tiles are stored; the tests do.
    private(set) var renderTask: Task<Void, Never>?

    private let base: CGImage
    private let renderer: any TileRendering
    private let imageSize: CGSize
    /// The keys the latest `reconcile` asked for. `generation` counts the calls that changed them.
    private var wanted: [UUID: TileKey] = [:]
    private var generation = 0

    init(base: CGImage, renderer: any TileRendering) {
        self.base = base
        self.renderer = renderer
        imageSize = CGSize(width: base.width, height: base.height)
    }

    /// The effects to tile, in creation order. An effect `transient` with the id of an effect in
    /// the document (one being moved or resized) takes that effect's place; a new one comes last.
    /// A transient drawing is ignored.
    nonisolated static func orderedEffects(in document: AnnotationDocument, transient: Annotation?) -> [Annotation] {
        var effects = document.effects
        guard let transient, transient.isEffect else { return effects }
        if let index = effects.firstIndex(where: { $0.id == transient.id }) {
            effects[index] = transient
        } else {
            effects.append(transient)
        }
        return effects
    }

    /// The key each effect's tile needs, by id. A redact's tile is its fill alone, so its `beneath`
    /// is empty. A blur's or pixelate's lists, in creation order, every earlier effect and every
    /// redact, earlier or later, whose rect meets its sample rect (`EffectGeometry.sampleRect`),
    /// plus everything beneath those: the tile's pixels came from them, so a change to any of them
    /// must change this key too. A redact drawn after a blur still lies under it, so the blur's
    /// margin never smears in the pixels the redact hides (spec 2.6), whatever the order.
    nonisolated static func keys(for effects: [Annotation], imageSize: CGSize) -> [UUID: TileKey] {
        var keys: [UUID: TileKey] = [:]
        var reach: [Set<Int>] = []
        for (index, effect) in effects.enumerated() {
            var below = Set<Int>()
            if !isRedact(effect) {
                let sample = sampleArea(of: effect, imageSize: imageSize)
                for other in effects.indices where (other < index || (other > index && isRedact(effects[other])))
                    && meets(effects[other], sample, imageSize: imageSize) {
                    below.insert(other)
                    // A later one is a redact, which has nothing beneath.
                    if other < index { below.formUnion(reach[other]) }
                }
            }
            reach.append(below)
            keys[effect.id] = TileKey(effect: effect, beneath: below.sorted().map { effects[$0] })
        }
        return keys
    }

    /// The tile to show for `effect` now, or nil while it is pending (the canvas then draws the
    /// placeholder). A stored tile counts only when its key equals the key the effect wants in
    /// `document` with `transient`.
    func currentTile(for effect: Annotation, in document: AnnotationDocument, transient: Annotation?) -> CGImage? {
        guard let entry = tiles[effect.id] else { return nil }
        // Every effect, not only those up to this one: a later redact can lie beneath it.
        let effects = Self.orderedEffects(in: document, transient: transient)
        guard let wanted = Self.keys(for: effects, imageSize: imageSize)[effect.id] else { return nil }
        return entry.key == wanted ? entry.image : nil
    }

    /// Brings the tiles in line with `document` and `transient`. Tiles of effects that are gone
    /// are dropped at once; the effects whose key changed render in `renderOrder` in one task.
    /// Call it after every change to the document or to the transient shape.
    func reconcile(document: AnnotationDocument, transient: Annotation?) {
        let effects = Self.orderedEffects(in: document, transient: transient)
        let keys = Self.keys(for: effects, imageSize: imageSize)
        // Same keys as the pass in flight or done (a commit of the dragged value): let it finish.
        guard keys != wanted else { return }
        wanted = keys
        generation += 1
        let gone = tiles.keys.filter { keys[$0] == nil }
        for id in gone { tiles[id] = nil }
        if !gone.isEmpty { onChange() }
        let stale = Self.renderOrder(effects.filter { tiles[$0.id]?.key != keys[$0.id] })
        guard !stale.isEmpty else {
            renderTask = nil
            return
        }
        let generation = generation
        renderTask = Task { [weak self] in
            await self?.render(stale, keys: keys, generation: generation)
        }
    }

    /// Every tile `document` needs, in creation order, for export: the stored tile when its key
    /// matches, otherwise a new render through the same renderer, so the export equals the
    /// preview. The transient shape is never exported. Leaves `tiles` unchanged.
    func allTiles(for document: AnnotationDocument) async -> [EffectTile] {
        let effects = document.effects
        let keys = Self.keys(for: effects, imageSize: imageSize)
        var done: [UUID: EffectTile] = [:]
        for effect in Self.renderOrder(effects) {
            guard let key = keys[effect.id] else { continue }
            // Fail closed: an effect whose direct beneath is missing a tile is left out, never
            // rendered over the raw pixels (a redact under it that failed to render).
            guard let beneath = directlyBeneath(key, tile: { done[$0] }) else { continue }
            let image: CGImage?
            if let entry = tiles[effect.id], entry.key == key {
                image = entry.image
            } else {
                image = await renderer.tile(for: effect, over: base, beneath: beneath)
            }
            // nil is a failure when the effect has pixels in the image: leave it out.
            guard let image else { continue }
            done[effect.id] = EffectTile(effect: effect, image: image)
        }
        return effects.compactMap { done[$0.id] }
    }

    // MARK: Private

    private func render(_ effects: [Annotation], keys: [UUID: TileKey], generation: Int) async {
        for effect in effects {
            guard generation == self.generation else { return }
            guard let key = keys[effect.id], tiles[effect.id]?.key != key else { continue }
            let beneath = directlyBeneath(key) { id in
                guard let entry = self.tiles[id], entry.key == keys[id] else { return nil }
                return EffectTile(effect: entry.key.effect, image: entry.image)
            }
            // A tile under this effect is missing (its render failed): rendering now would
            // composite over the raw pixels it should cover, so end the pass.
            guard let beneath else { return fail(effect) }
            let image = await renderer.tile(for: effect, over: base, beneath: beneath)
            // A newer reconcile started while this tile rendered: drop it, that pass owns the cache.
            guard generation == self.generation else { return }
            guard let image else {
                // nil for an effect with pixels in the image is a failed render, not a missing
                // tile: later effects may sample this one, so end the pass and leave them pending.
                // Only an effect wholly outside the image has nothing to show, and may go on.
                if EffectTile.rect(for: effect, imageSize: imageSize) != nil { return fail(effect) }
                tiles[effect.id] = nil
                onChange()
                continue
            }
            tiles[effect.id] = (key, image)
            onChange()
        }
    }

    /// Ends a pass at `effect`: it has no tile, and the effects after it stay pending until a
    /// later `reconcile` with changed keys renders them.
    private func fail(_ effect: Annotation) {
        tiles[effect.id] = nil
        onChange()
    }

    /// The tiles the renderer composites under `key.effect`: those of the effects in `beneath`
    /// whose rects meet its sample rect, in creation order, so a redact created after the effect
    /// is drawn over every earlier tile. `tile` returns a tile only when it matches the current key
    /// of that effect. Nil when one of those effects has no tile: the effect must
    /// not be rendered over the pixels that tile should have covered.
    private func directlyBeneath(_ key: TileKey, tile: (UUID) -> EffectTile?) -> [EffectTile]? {
        let sample = Self.sampleArea(of: key.effect, imageSize: imageSize)
        var result: [EffectTile] = []
        for earlier in key.beneath where Self.meets(earlier, sample, imageSize: imageSize) {
            guard let found = tile(earlier.id) else { return nil }
            result.append(found)
        }
        return result
    }

    /// `effects` with the redacts first, each part in creation order: a blur or pixelate may sample
    /// a redact created after it, and a redact's tile needs no other.
    nonisolated private static func renderOrder(_ effects: [Annotation]) -> [Annotation] {
        effects.filter(isRedact) + effects.filter { !isRedact($0) }
    }

    nonisolated private static func isRedact(_ effect: Annotation) -> Bool {
        if case .redact = effect { return true }
        return false
    }

    /// The pixels an effect reads, rounded out to whole pixels and clipped to the image.
    nonisolated private static func sampleArea(of effect: Annotation, imageSize: CGSize) -> CGRect {
        ImageRects.integral(EffectGeometry.sampleRect(of: effect, imageSize: imageSize), clippedTo: imageSize)
    }

    /// Whether `earlier`'s tile, its rect rounded out to whole pixels, shares at least one pixel
    /// with `sample`. Rects that only touch along an edge share none.
    nonisolated private static func meets(_ earlier: Annotation, _ sample: CGRect, imageSize: CGSize) -> Bool {
        guard let rect = earlier.effectRect else { return false }
        let tile = ImageRects.integral(rect, clippedTo: imageSize)
        return !tile.isEmpty && !sample.isEmpty && tile.intersects(sample)
    }
}
