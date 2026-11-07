import AppKit
import QuartzCore

/// The capture and its effect tiles, as layers placed by `transform`: the image as one layer per
/// `ImageTiling` tile (one for any image up to 16,384 px on a side, stacked strips for a taller
/// scrolling capture, since a GPU texture holds no more), then one sublayer per effect tile, in
/// creation order. Zoom and pan only move layer frames, and the view is viewport-sized, so there
/// is no document-sized backing store and no `_NSTiledLayer`. Clicks pass through to the canvas
/// above.
///
/// With a background (spec 2.11, Editor), three more layers are placed by the transform: the fill
/// behind everything, reaching past the content by the padding; a shadow under the rounded
/// content rect; and a rounded mask over the container that holds the image and effect layers.
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
    /// An effect's tile: its layer, the image it shows and the rect it covers in image pixels.
    private struct Tile {
        let id: UUID
        let layer: CALayer
        var image: CGImage?
        var rect: CGRect
    }
    /// The effect tiles in creation order.
    private var tiles: [Tile] = []
    /// The magnification filter every image and tile layer has: nearest from 2 device pixels per
    /// image pixel up, so redacted pixels read exactly when zoomed in, linear below. A new layer
    /// gets it at once; a pan or zoom that keeps it writes nothing.
    private var magnificationFilter: CALayerContentsFilter = .linear

    /// The background shown behind the capture, nil for none, and the capture's scale, which
    /// sizes the shadow.
    private var background: ShownBackground?
    private var captureScale: CGFloat = 1
    /// The fill, rendered off the main actor at most 2,048 px on its long side and stretched over
    /// the background's rect. Nil until the first render arrives.
    var backgroundFill: CGImage? {
        didSet {
            guard backgroundFill !== oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backgroundLayer.contents = backgroundFill
            CATransaction.commit()
        }
    }
    let backgroundLayer = CALayer()
    /// No contents: only its shadow shows, cast by `shadowPath`.
    let shadowLayer = CALayer()
    /// Holds the image and effect layers, so one mask rounds them all.
    private let contentLayer = CALayer()
    /// The content container's mask while a background is shown.
    let roundedMask = CALayer()

    /// The image layers, then the effect-tile layers, in creation order.
    var contentLayers: [CALayer] { contentLayer.sublayers ?? [] }
    var isContentMasked: Bool { contentLayer.mask != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        backgroundLayer.contentsGravity = .resize
        backgroundLayer.magnificationFilter = .linear
        backgroundLayer.minificationFilter = .trilinear
        backgroundLayer.isHidden = true
        shadowLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        shadowLayer.shadowOpacity = Float(BackgroundCompositor.shadowAlpha)
        shadowLayer.shadowOffset = .zero
        shadowLayer.isHidden = true
        roundedMask.backgroundColor = CGColor(gray: 0, alpha: 1)
        roundedMask.cornerCurve = .circular  // as CGPath(roundedRect:) draws in the export
        installLayers()
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLayers()
    }

    /// The fill, the shadow and the content container, in that order, under the view's layer.
    /// The layer may not exist yet when the view is made, so every change calls this.
    private func installLayers() {
        guard let layer, contentLayer.superlayer !== layer else { return }
        layer.sublayers = [backgroundLayer, shadowLayer, contentLayer]
    }

    /// Shows `background` behind the capture, or hides it for nil. The fill arrives separately, as
    /// `backgroundFill`.
    func setBackground(_ background: ShownBackground?, captureScale: CGFloat) {
        guard background != self.background || captureScale != self.captureScale else { return }
        self.background = background
        self.captureScale = captureScale
        layoutLayers()
    }

    /// One entry per effect on screen, in creation order. A nil image hides that tile; the canvas
    /// draws its placeholder. Layers for ids no longer listed are removed; a layer whose image is
    /// the same object keeps its contents.
    func setTiles(_ shown: [(id: UUID, rect: CGRect, image: CGImage?)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var existing = Dictionary(tiles.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        tiles = shown.map { entry in
            var tile = existing.removeValue(forKey: entry.id)
                ?? Tile(id: entry.id, layer: makeTileLayer(), image: nil, rect: .zero)
            if tile.image !== entry.image { tile.layer.contents = entry.image }
            tile.layer.isHidden = entry.image == nil
            tile.image = entry.image
            tile.rect = entry.rect
            return tile
        }
        installLayers()
        contentLayer.sublayers = imageLayers + tiles.map(\.layer)
        CATransaction.commit()
        layoutLayers()
    }

    /// Replaces the image layers with one per tile, under the effect tiles.
    private func setBaseTiles(_ crops: [(rect: CGRect, image: CGImage)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseTiles = crops
        imageLayers = crops.map { crop in
            let imageLayer = makeTileLayer()
            imageLayer.contents = crop.image
            return imageLayer
        }
        installLayers()
        contentLayer.sublayers = imageLayers + tiles.map(\.layer)
        CATransaction.commit()
        layoutLayers()
    }

    /// A layer with the filters of the moment: `magnificationFilter`, and trilinear minification.
    private func makeTileLayer() -> CALayer {
        let tileLayer = CALayer()
        tileLayer.contentsGravity = .resize
        tileLayer.magnificationFilter = magnificationFilter
        tileLayer.minificationFilter = .trilinear
        return tileLayer
    }

    /// Frames every layer at `transform.viewRect` of its image-pixel rect, so the image's layers
    /// meet edge to edge at any zoom and pan, and gives every layer the new magnification filter
    /// when the zoom crosses 2 device pixels per image pixel. The background's layers follow the
    /// same transform.
    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        installLayers()
        contentLayer.frame = bounds
        layoutBackground()
        let filter: CALayerContentsFilter = transform.zoom * (window?.backingScaleFactor ?? 2) >= 2 ? .nearest : .linear
        let filterChanged = filter != magnificationFilter
        magnificationFilter = filter
        for (imageLayer, crop) in zip(imageLayers, baseTiles) {
            imageLayer.frame = transform.viewRect(crop.rect)
            if filterChanged { imageLayer.magnificationFilter = filter }
        }
        for tile in tiles {
            tile.layer.frame = transform.viewRect(tile.rect)
            if filterChanged { tile.layer.magnificationFilter = filter }
        }
        CATransaction.commit()
    }

    /// The fill at the background's rect; the shadow and the mask at the rounded content rect,
    /// with the export's shadow (offset, blur, black at 35 %) in view points. A layer's shadow
    /// radius is half a CoreGraphics shadow blur. The shadow is moved down by its offset rather
    /// than given a `shadowOffset`, whose direction a flipped layer tree would turn around.
    private func layoutBackground() {
        guard let background else {
            backgroundLayer.isHidden = true
            shadowLayer.isHidden = true
            contentLayer.mask = nil
            return
        }
        let zoom = transform.zoom
        let content = transform.viewRect(background.contentRect)
        // At most half the shorter side, which CGPath requires; zooming must not round past it.
        let radius = min(background.radius * zoom, content.width / 2, content.height / 2)
        backgroundLayer.isHidden = false
        backgroundLayer.frame = transform.viewRect(background.canvasRect)

        shadowLayer.isHidden = !background.style.shadow
        let points = captureScale * zoom  // view points per point of the style
        shadowLayer.frame = content.offsetBy(dx: 0, dy: BackgroundCompositor.shadowOffset * points)
        shadowLayer.shadowPath = CGPath(roundedRect: shadowLayer.bounds, cornerWidth: radius, cornerHeight: radius,
                                        transform: nil)
        shadowLayer.shadowRadius = BackgroundCompositor.shadowBlur * points / 2

        roundedMask.frame = content
        roundedMask.cornerRadius = radius
        contentLayer.mask = roundedMask
    }
}
