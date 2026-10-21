import CoreGraphics

/// One recognised line or run of text. The box is normalised with its origin at the bottom left,
/// as Vision gives it.
nonisolated struct TextPiece: Equatable, Sendable {
    var text: String
    var box: CGRect
}

/// The two-dimensional codes TidyShot reads.
nonisolated enum CodeSymbology: Equatable, Sendable {
    case qr, microQR, aztec, dataMatrix, pdf417
}

/// One decoded code. The box is normalised with its origin at the bottom left.
nonisolated struct CodePiece: Equatable, Sendable {
    var payload: String
    var symbology: CodeSymbology
    var box: CGRect
}

/// What Vision found in an image, in Vision's order.
nonisolated struct TextScan: Equatable, Sendable {
    var pieces: [TextPiece]
    var codes: [CodePiece]
}
