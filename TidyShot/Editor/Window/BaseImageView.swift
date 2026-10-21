import AppKit
import QuartzCore

/// The capture and its effect tiles, as layers placed by `transform`: the image as one layer per
/// `ImageTiling` tile (one for any image up to 16,384 px on a side, stacked strips for a taller
/// scrolling capture, since a GPU texture holds no more), then one sublayer per effect tile, in
/// creation order. Zoom and pan only move layer frames, and the view is viewport-sized, so there
/// is no document-sized backing store and no `_NSTiledLayer`. Clicks pass through to the canvas
/// above.
final class BaseImageView: NSView {
    var image: CGImage? {
        didSet {
            setBaseTiles(image.map { ImageTiling.crops(of: $0) } ?? [])
        }
    }

    /// The image as shown: each layer's crop and the rect it covers in image pixels. The canvas's
    /// highlighter backdrop draws these, so its copy matches the layers.
    private(set) var baseTiles: [(rect: CGRect, image: CGImage)] = []

    var transform = CanvasTransform(zoom: 1, offset: .zero) {
        didSet {
            if transform != oldValue { layoutLayers() }
        }
    }

    /// One layer per entry of `baseTiles`, in the same order.
    private var imageLayers: [CALayer] = []
    /// Tile layers by effect id, the image each shows and the rect it covers in image pixels.
    private var tileLayers: [UUID: CALayer] = [:]
    private var tileImages: [UUID: CGImage] = [:]
    private var tileRects: [UUID: CGRect] = [:]
    private var tileOrder: [UUID] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // AppKit sets geometryFlipped on a flipped view's layer, so sublayer frames are top-left
    // view points like everything else here.
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutLayers()
    }

    /// One entry per effect on screen, in creation order. A nil image hides that tile; the canvas
    /// draws its placeholder. Layers for ids no longer listed are removed.
    func setTiles(_ tiles: [(id: UUID, rect: CGRect, image: CGImage?)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var layers: [UUID: CALayer] = [:]
        var images: [UUID: CGImage] = [:]
        var rects: [UUID: CGRect] = [:]
        for tile in tiles {
            let tileLayer = tileLayers[tile.id] ?? makeTileLayer()
            if tileImages[tile.id] !== tile.image {
                tileLayer.contents = tile.image
            }
            tileLayer.isHidden = tile.image == nil
            layers[tile.id] = tileLayer
            images[tile.id] = tile.image
            rects[tile.id] = tile.rect
        }
        tileLayers = layers
        tileImages = images
        tileRects = rects
        tileOrder = tiles.map(\.id)
        layer?.sublayers = imageLayers + tileOrder.compactMap { layers[$0] }
        CATransaction.commit()
        layoutLayers()
    }

    /// Replaces the image layers with one per tile, under the effect tiles.
    private func setBaseTiles(_ tiles: [(rect: CGRect, image: CGImage)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseTiles = tiles
        imageLayers = tiles.map { tile in
            let imageLayer = makeTileLayer()
            imageLayer.contents = tile.image
            return imageLayer
        }
        layer?.sublayers = imageLayers + tileOrder.compactMap { tileLayers[$0] }
        CATransaction.commit()
        layoutLayers()
    }

    private func makeTileLayer() -> CALayer {
        let tileLayer = CALayer()
        tileLayer.contentsGravity = .resize
        return tileLayer
    }

    /// Frames every layer at `transform.viewRect` of its image-pixel rect, so the image's layers
    /// meet edge to edge at any zoom and pan. Nearest-neighbour magnification from 2 device pixels
    /// per image pixel up, so redacted pixels read exactly when zoomed in; linear below; trilinear
    /// minification.
    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let filter: CALayerContentsFilter = transform.zoom * (window?.backingScaleFactor ?? 2) >= 2 ? .nearest : .linear
        for (imageLayer, tile) in zip(imageLayers, baseTiles) {
            imageLayer.frame = transform.viewRect(tile.rect)
            imageLayer.magnificationFilter = filter
            imageLayer.minificationFilter = .trilinear
        }
        for id in tileOrder {
            guard let tileLayer = tileLayers[id], let rect = tileRects[id] else { continue }
            tileLayer.frame = transform.viewRect(rect)
            tileLayer.magnificationFilter = filter
            tileLayer.minificationFilter = .trilinear
        }
        CATransaction.commit()
    }
}
