import AppKit

enum Pasteboard {
    /// Puts the image on the general pasteboard as PNG and TIFF. The TIFF rep's size is set in
    /// points so Retina images paste at their on-screen size. Like every `copy` here, returns the
    /// pasteboard's `changeCount` after the write, which the editor's clipboard rule compares
    /// later (`EditorClipboard`).
    @discardableResult
    static func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiff = tiffData(of: image, scale: scale) {
            item.setData(tiff, forType: .tiff)
        }
        return write([item])
    }

    /// Puts already encoded PNG and TIFF data on the general pasteboard; the TIFF comes from
    /// `tiffData(of:scale:)`, made off the main actor. A nil `tiffData` leaves the PNG alone.
    @discardableResult
    static func copy(pngData: Data, tiffData: Data?) -> Int {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiffData {
            item.setData(tiffData, forType: .tiff)
        }
        return write([item])
    }

    /// Puts the image on the general pasteboard as TIFF only, for when PNG encoding failed.
    /// The rep's size is set in points, as above.
    @discardableResult
    static func copy(image: CGImage, scale: CGFloat) -> Int {
        let item = NSPasteboardItem()
        if let tiff = tiffData(of: image, scale: scale) {
            item.setData(tiff, forType: .tiff)
        }
        return write([item])
    }

    /// The image as TIFF with its rep's size in points, so a Retina image pastes at its on-screen
    /// size. Touches no shared state, so it can run in a detached task (Copy Image).
    nonisolated static func tiffData(of image: CGImage, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return rep.tiffRepresentation
    }

    /// Replaces the pasteboard contents with a file reference, so a paste in Finder copies the
    /// file and a paste in Slack or Mail attaches it.
    @discardableResult
    static func copy(fileURL: URL) -> Int {
        write([fileURL as NSURL])
    }

    /// Replaces the pasteboard contents with `url`, as plain text and as a URL.
    @discardableResult
    static func copy(url: URL) -> Int {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .string)
        item.setString(url.absoluteString, forType: .URL)
        return write([item])
    }

    /// The private type of an object copy (`AnnotationClip`).
    static let annotationClipType = NSPasteboard.PasteboardType(AnnotationClip.pasteboardTypeName)

    /// Replaces the pasteboard contents with one copied annotation, under the private type only:
    /// pasting into another app pastes nothing.
    @discardableResult
    static func copy(annotationClip data: Data) -> Int {
        let item = NSPasteboardItem()
        item.setData(data, forType: annotationClipType)
        return write([item])
    }

    /// The copied annotation's data, or nil.
    static func annotationClipData() -> Data? {
        NSPasteboard.general.data(forType: annotationClipType)
    }

    /// Whether an object copy is on the pasteboard. Checks the types only, so no data is read.
    static var hasAnnotationClip: Bool {
        NSPasteboard.general.availableType(from: [annotationClipType]) != nil
    }

    /// Replaces the general pasteboard's contents with `objects` and returns its `changeCount`,
    /// read after the write.
    private static func write(_ objects: [any NSPasteboardWriting]) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(objects)
        return pasteboard.changeCount
    }
}
