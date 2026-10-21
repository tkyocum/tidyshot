import CoreGraphics

/// Joins recognised pieces into text. Vision's order is kept, because it already follows columns.
nonisolated enum TextJoiner {
    /// How far left of the previous piece's right edge a piece may start and still continue its line.
    private static let leftSlack: CGFloat = 0.01

    static func join(_ pieces: [TextPiece]) -> String {
        var result = ""
        var previous: CGRect?
        for piece in pieces {
            let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if let previous {
                result += continuesLine(piece.box, after: previous) ? " " : "\n"
            }
            result += text
            previous = piece.box
        }
        return result
    }

    /// True when `box` overlaps `previous` vertically by at least half the smaller height and does
    /// not start left of `previous`'s right edge (less the slack).
    private static func continuesLine(_ box: CGRect, after previous: CGRect) -> Bool {
        let overlap = min(box.maxY, previous.maxY) - max(box.minY, previous.minY)
        guard overlap >= min(box.height, previous.height) / 2 else { return false }
        return box.minX >= previous.maxX - leftSlack
    }
}
