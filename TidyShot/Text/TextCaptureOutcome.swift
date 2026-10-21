import Foundation

/// What Capture Text does with a scan: the clipboard text and the notification to post.
nonisolated struct TextCaptureOutcome: Equatable, Sendable {
    /// Nil when nothing was found, so the clipboard is left alone.
    let clipboard: String?
    let title: String
    let body: String
    /// Set only for a single payload that is a web link, so the notification opens it on click.
    let openURL: URL?

    static let previewLimit = 80

    /// Codes win over text: the clipboard gets their payloads, each once, in Vision's order.
    static func decide(_ scan: TextScan) -> TextCaptureOutcome {
        var payloads: [String] = []
        var firstSymbology: CodeSymbology?
        for code in scan.codes where !code.payload.isEmpty && !payloads.contains(code.payload) {
            if payloads.isEmpty { firstSymbology = code.symbology }
            payloads.append(code.payload)
        }

        if let first = payloads.first, let symbology = firstSymbology {
            let title: String
            if payloads.count > 1 {
                title = "\(payloads.count) codes copied"
            } else {
                title = symbology == .qr || symbology == .microQR ? "QR code copied" : "Code copied"
            }
            return TextCaptureOutcome(
                clipboard: payloads.joined(separator: "\n"), title: title, body: preview(first),
                openURL: payloads.count == 1 ? webURL(first) : nil)
        }

        let text = TextJoiner.join(scan.pieces)
        if !text.isEmpty {
            return TextCaptureOutcome(clipboard: text, title: "Text copied", body: preview(text), openURL: nil)
        }
        return TextCaptureOutcome(
            clipboard: nil, title: "No text found",
            body: "TidyShot found no text or QR code in the selection.", openURL: nil)
    }

    /// The first line of `text`, cut to `previewLimit` characters with `…` when it was longer.
    static func preview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.prefix { !$0.isNewline }
        guard firstLine.count > previewLimit else { return String(firstLine) }
        return String(firstLine.prefix(previewLimit)) + "…"
    }

    private static func webURL(_ payload: String) -> URL? {
        guard let url = URL(string: payload),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
