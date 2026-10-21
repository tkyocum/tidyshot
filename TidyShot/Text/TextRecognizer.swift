import CoreGraphics
import Vision

/// Reads text and two-dimensional codes from an image with Vision.
nonisolated struct TextRecognizer: Sendable {
    /// Runs off the main actor: the first text request after a restart can take about 24 s while
    /// the system loads its model.
    @concurrent
    func recognize(_ image: CGImage) async throws -> TextScan {
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        let observations = try await textRequest.perform(on: image)
        let pieces = observations.compactMap { observation -> TextPiece? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return TextPiece(text: candidate.string, box: observation.boundingBox.cgRect)
        }

        // Two-dimensional codes only: stripes in a screenshot can read as one-dimensional barcodes.
        var barcodeRequest = DetectBarcodesRequest()
        barcodeRequest.symbologies = [.qr, .microQR, .aztec, .dataMatrix, .pdf417]
        let barcodes = try await barcodeRequest.perform(on: image)
        let codes = barcodes.compactMap { barcode -> CodePiece? in
            guard let payload = barcode.payloadString, !payload.isEmpty,
                  let symbology = Self.symbology(barcode.symbology)
            else { return nil }
            return CodePiece(payload: payload, symbology: symbology, box: barcode.boundingBox.cgRect)
        }
        return TextScan(pieces: pieces, codes: codes)
    }

    private static func symbology(_ symbology: BarcodeSymbology) -> CodeSymbology? {
        switch symbology {
        case .qr: .qr
        case .microQR: .microQR
        case .aztec: .aztec
        case .dataMatrix: .dataMatrix
        case .pdf417: .pdf417
        default: nil
        }
    }
}
