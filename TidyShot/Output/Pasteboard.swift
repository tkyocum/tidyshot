import AppKit

enum Pasteboard {
    /// Puts the image on the general pasteboard as PNG and TIFF. The TIFF rep's size is set in
    /// points so Retina images paste at their on-screen size.
    static func copy(image: CGImage, pngData: Data, scale: CGFloat) {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiff = tiffData(of: image, scale: scale) {
            item.setData(tiff, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Puts already encoded PNG and TIFF data on the general pasteboard; the TIFF comes from
    /// `tiffData(of:scale:)`, made off the main actor. A nil `tiffData` leaves the PNG alone.
    static func copy(pngData: Data, tiffData: Data?) {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiffData {
            item.setData(tiffData, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Puts the image on the general pasteboard as TIFF only, for when PNG encoding failed.
    /// The rep's size is set in points, as above.
    static func copy(image: CGImage, scale: CGFloat) {
        let item = NSPasteboardItem()
        if let tiff = tiffData(of: image, scale: scale) {
            item.setData(tiff, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
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
    static func copy(fileURL: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
    }

    /// Replaces the pasteboard contents with `url`, as plain text and as a URL.
    static func copy(url: URL) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .string)
        item.setString(url.absoluteString, forType: .URL)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
