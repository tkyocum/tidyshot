import CoreGraphics
import Foundation
import Testing
@testable import TidyShot
/// Captures as the save path takes them (`AppCoordinator.save(_:from:intent:)`): an image of a pixel size at a scale,
/// and where it came from. No ScreenCaptureKit object is made; the display id is the suite's own number.
nonisolated enum CaptureSamples {
    static let displayID: CGDirectDisplayID = 1
    /// A red capture of `width` by `height` pixels at `scale`, white when `white`.
    static func image(width: Int, height: Int, scale: CGFloat = 2, white: Bool = false) throws -> ScaledImage { ScaledImage(image: try EditorPixels.image(width: width, height: height, white: white), scale: scale) }
    static let display = CaptureOrigin(kind: .display, displayID: displayID)
    static let window = CaptureOrigin(kind: .window, displayID: displayID)
    static func area(_ rect: CGRect = CGRect(x: 100, y: 80, width: 200, height: 150)) -> CaptureOrigin { CaptureOrigin(kind: .area(rect), displayID: displayID) }
    /// The names of the files directly in `folder`, sorted; none when it does not exist.
    static func fileNames(in folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted() }
}
