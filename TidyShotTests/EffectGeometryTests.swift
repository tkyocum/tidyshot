import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct EffectGeometryTests {
    /// The 64 by 48 image the effects sit on.
    let size = CGSize(width: 64, height: 48)

    func region(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Region {
        Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func blurSampleRectGrowsByThreeSigma() {
        // Sigma 4 reads 12 px beyond the rect on every side.
        #expect(EffectGeometry.sampleRect(of: .blur(region(20, 15, 10, 8), radius: 4), imageSize: size)
                == CGRect(x: 8, y: 3, width: 34, height: 32))
        // Sigma 2.5 reads ceil(7.5) = 8 px.
        #expect(EffectGeometry.sampleRect(of: .blur(region(20, 15, 10, 8), radius: 2.5), imageSize: size)
                == CGRect(x: 12, y: 7, width: 26, height: 24))
        // Near a corner the margin is clipped to the image.
        #expect(EffectGeometry.sampleRect(of: .blur(region(2, 2, 10, 10), radius: 4), imageSize: size)
                == CGRect(x: 0, y: 0, width: 24, height: 24))
    }

    @Test func pixelateSampleRectIsBlockSnapped() {
        #expect(EffectGeometry.sampleRect(of: .pixelate(region(13, 7, 20, 10), block: 6), imageSize: size)
                == CGRect(x: 12, y: 6, width: 24, height: 12))
        // The last cells reach column 66; the sample stops at the image's edge.
        #expect(EffectGeometry.sampleRect(of: .pixelate(region(60, 44, 4, 4), block: 6), imageSize: size)
                == CGRect(x: 60, y: 42, width: 4, height: 6))
    }

    @Test func redactSampleRectIsItself() {
        let fill = EditorPalette.defaultRedact
        #expect(EffectGeometry.sampleRect(of: .redact(region(5, 6, 7, 8), fill: fill), imageSize: size)
                == CGRect(x: 5, y: 6, width: 7, height: 8))
        // Rounded out to the pixels its tile covers.
        #expect(EffectGeometry.sampleRect(of: .redact(region(5.5, 6, 7, 8.2), fill: fill), imageSize: size)
                == CGRect(x: 5, y: 6, width: 8, height: 9))
        // A drawing has no tile and samples nothing.
        let box = ShapeBox(id: UUID(), rect: CGRect(x: 5, y: 6, width: 7, height: 8), color: EditorPalette.defaultStroke, lineWidth: 8)
        #expect(EffectGeometry.sampleRect(of: .rectangle(box), imageSize: size) == .zero)
    }

    /// Cells sit on multiples of the block from the top-left pixel, wherever the region is.
    @Test func mosaicRectAnchoredToImageGrid() {
        #expect(EffectGeometry.mosaicRect(CGRect(x: 13, y: 7, width: 20, height: 10), block: 6)
                == CGRect(x: 12, y: 6, width: 24, height: 12))
        // Dragged 4 px right: the cells it still covers are the same cells.
        #expect(EffectGeometry.mosaicRect(CGRect(x: 17, y: 7, width: 20, height: 10), block: 6)
                == CGRect(x: 12, y: 6, width: 30, height: 12))
        // An aligned rect is unchanged, and fractional edges round out to whole cells.
        #expect(EffectGeometry.mosaicRect(CGRect(x: 12, y: 6, width: 24, height: 12), block: 6)
                == CGRect(x: 12, y: 6, width: 24, height: 12))
        #expect(EffectGeometry.mosaicRect(CGRect(x: 12.5, y: 6, width: 5, height: 0.5), block: 6)
                == CGRect(x: 12, y: 6, width: 6, height: 6))
        // Not clipped: the renderer decides the edge cells.
        #expect(EffectGeometry.mosaicRect(CGRect(x: 60, y: 44, width: 4, height: 4), block: 6)
                == CGRect(x: 60, y: 42, width: 6, height: 6))
    }
}
