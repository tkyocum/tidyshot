import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct CustomBackgroundStoreTests {
    let dir: URL
    let store: CustomBackgroundStore

    init() {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        store = CustomBackgroundStore(directory: dir.appending(path: "Backgrounds"))
    }

    /// A PNG of `width` x `height` filled with `rgb`, written into the test folder.
    private func pngFile(width: Int, height: Int, rgb: (CGFloat, CGFloat, CGFloat), name: String) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = dir.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try ImageEncoder.pngData(from: context.makeImage()!, scale: 1).write(to: url)
        return url
    }

    /// The RGBA bytes of the pixel at (0, 0).
    private func firstPixel(of image: CGImage) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel
    }

    @Test func emptyUntilAnImageIsStored() {
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!store.hasImage)
        #expect(store.image() == nil)
        #expect(CustomBackgroundStore.maximumSide == 6_000)
    }

    @Test func storesTheImageAsCustomPNGAndReadsItBack() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.store(contentsOf: pngFile(width: 40, height: 30, rgb: (1, 0, 0), name: "red.png"))
        #expect(store.hasImage)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "Backgrounds/custom.png").path(percentEncoded: false)))
        let image = try #require(store.image())
        #expect(image.width == 40 && image.height == 30)
        #expect(firstPixel(of: image) == [255, 0, 0, 255])
    }

    @Test func aSecondImageReplacesTheFirst() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.store(contentsOf: pngFile(width: 40, height: 30, rgb: (1, 0, 0), name: "red.png"))
        try store.store(contentsOf: pngFile(width: 20, height: 50, rgb: (0, 0, 1), name: "blue.png"))
        let image = try #require(store.image())
        #expect(image.width == 20 && image.height == 50)
        #expect(firstPixel(of: image) == [0, 0, 255, 255])
    }

    @Test func aLargeImageIsScaledDownToTheMaximumSide() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.store(contentsOf: pngFile(width: 12_000, height: 60, rgb: (0, 1, 0), name: "wide.png"))
        let image = try #require(store.image())
        #expect(image.width == 6_000)
        #expect(image.height == 30)
    }

    @Test func anUndecodableFileIsRefusedAndNothingChanges() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let junk = dir.appending(path: "junk.png")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not an image".utf8).write(to: junk)

        #expect(throws: CustomBackgroundStore.StoreError.notAnImage) { try store.store(contentsOf: junk) }
        #expect(!store.hasImage)

        try store.store(contentsOf: pngFile(width: 40, height: 30, rgb: (1, 0, 0), name: "red.png"))
        #expect(throws: CustomBackgroundStore.StoreError.notAnImage) { try store.store(contentsOf: junk) }
        let image = try #require(store.image())
        #expect(image.width == 40 && image.height == 30)
    }

    @Test func aMissingFileIsRefused() {
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: CustomBackgroundStore.StoreError.notAnImage) {
            try store.store(contentsOf: dir.appending(path: "missing.png"))
        }
        #expect(!store.hasImage)
    }
}
