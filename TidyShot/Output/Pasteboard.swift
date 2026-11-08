import AppKit

/// What goes on the clipboard beside a PNG, worked out off the main actor; `SystemClipboard` writes.
enum Pasteboard {
    /// The longest side, in pixels, of an image whose PNG on the clipboard gets a TIFF beside it.
    /// The TIFF is uncompressed: for a 3094 x 65,536 scrolling capture it is about 580 MB, and
    /// making it peaks at about 1.2 GB over the image, so a longer image goes on as PNG only,
    /// which every current Mac app reads. 16,384 was the scrolling capture's cap before it rose.
    nonisolated static let tiffMaxSide = 16_384

    /// Whether an image of this size gets a TIFF beside its PNG on the clipboard.
    nonisolated static func includesTIFF(pixelWidth: Int, pixelHeight: Int) -> Bool {
        pixelWidth <= tiffMaxSide && pixelHeight <= tiffMaxSide
    }

    /// The TIFF to put beside the image's PNG: `tiffData(of:scale:)`, or nil above `tiffMaxSide`.
    nonisolated static func companionTIFF(of image: CGImage, scale: CGFloat) -> Data? {
        guard includesTIFF(pixelWidth: image.width, pixelHeight: image.height) else { return nil }
        return tiffData(of: image, scale: scale)
    }

    /// The image as TIFF with its rep's size in points, so a Retina image pastes at its on-screen
    /// size. Touches no shared state, so it can run in a detached task (Copy Image).
    nonisolated static func tiffData(of image: CGImage, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return rep.tiffRepresentation
    }

    /// The private type of an object copy (`AnnotationClip`).
    static let annotationClipType = NSPasteboard.PasteboardType(AnnotationClip.pasteboardTypeName)
}

/// The general pasteboard as the coordinator uses it (harness design 2.2): `SystemClipboard` in the
/// app, a fake in the suite. Each `copy` returns the change count after the write.
protocol Clipboard: AnyObject {
    var changeCount: Int { get }
    /// Replaces the contents with `string` as plain text (Capture Text).
    func setString(_ string: String)
    @discardableResult func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int
    @discardableResult func copy(pngData: Data, tiffData: Data?) -> Int
    @discardableResult func copy(tiffData: Data?) -> Int
    @discardableResult func copy(fileURL: URL) -> Int
    @discardableResult func copy(url: URL) -> Int
    @discardableResult func copy(annotationClip data: Data) -> Int
    func annotationClipData() -> Data?
    var hasAnnotationClip: Bool { get }
}

/// `NSPasteboard.general`. Each `copy` replaces the contents and returns the pasteboard's
/// `changeCount` after the write, which the editor's clipboard rule compares later (`EditorClipboard`).
final class SystemClipboard: Clipboard {
    var changeCount: Int { NSPasteboard.general.changeCount }

    func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// The image as PNG and, up to `Pasteboard.tiffMaxSide`, TIFF. The TIFF rep's size is set in
    /// points so Retina images paste at their on-screen size.
    @discardableResult func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int {
        copy(pngData: pngData, tiffData: Pasteboard.companionTIFF(of: image, scale: scale))
    }

    /// Already encoded PNG and TIFF data; the TIFF comes from `Pasteboard.companionTIFF(of:scale:)`,
    /// made off the main actor. A nil `tiffData` leaves the PNG alone.
    @discardableResult func copy(pngData: Data, tiffData: Data?) -> Int {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiffData {
            item.setData(tiffData, forType: .tiff)
        }
        return write([item])
    }

    /// TIFF data alone, for when PNG encoding failed. It is the only copy of the image there, so
    /// callers make it at any size, off the main actor (`Pasteboard.tiffData(of:scale:)`). Nil
    /// data leaves an empty pasteboard item out.
    @discardableResult func copy(tiffData: Data?) -> Int {
        let item = NSPasteboardItem()
        if let tiffData {
            item.setData(tiffData, forType: .tiff)
        }
        return write([item])
    }

    /// A file reference, so a paste in Finder copies the file and a paste in Slack or Mail attaches it.
    @discardableResult func copy(fileURL: URL) -> Int {
        write([fileURL as NSURL])
    }

    /// `url`, as plain text and as a URL.
    @discardableResult func copy(url: URL) -> Int {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .string)
        item.setString(url.absoluteString, forType: .URL)
        return write([item])
    }

    /// One copied annotation, under the private type only: pasting into another app pastes nothing.
    @discardableResult func copy(annotationClip data: Data) -> Int {
        let item = NSPasteboardItem()
        item.setData(data, forType: Pasteboard.annotationClipType)
        return write([item])
    }

    /// The copied annotation's data, or nil.
    func annotationClipData() -> Data? {
        NSPasteboard.general.data(forType: Pasteboard.annotationClipType)
    }

    /// Whether an object copy is on the pasteboard. Checks the types only, so no data is read.
    var hasAnnotationClip: Bool {
        NSPasteboard.general.availableType(from: [Pasteboard.annotationClipType]) != nil
    }

    private func write(_ objects: [any NSPasteboardWriting]) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(objects)
        return pasteboard.changeCount
    }
}
