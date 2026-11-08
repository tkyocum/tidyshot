import CoreGraphics

/// What a capture sits on: a fill, padding around the capture, rounded corners, a shadow and an
/// aspect ratio for the whole picture. Every field decodes with `decodeIfPresent` and falls back
/// to its default, so older or partial JSON still loads.
nonisolated struct BackgroundStyle: Codable, Equatable, Sendable {
    var fill: BackgroundFill = .gradient(0)
    /// In points, 0 to 160.
    var padding: Double = 48
    /// In points, 0 to 40.
    var cornerRadius: Double = 12
    var shadow: Bool = true
    var aspect: BackgroundAspect = .auto
}

nonisolated extension BackgroundStyle {
    /// In an extension, so the memberwise `init(fill:padding:cornerRadius:shadow:aspect:)` stays.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        fill = try container.decodeIfPresent(BackgroundFill.self, forKey: .fill) ?? fill
        padding = try container.decodeIfPresent(Double.self, forKey: .padding) ?? padding
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius
        shadow = try container.decodeIfPresent(Bool.self, forKey: .shadow) ?? shadow
        aspect = try container.decodeIfPresent(BackgroundAspect.self, forKey: .aspect) ?? aspect
    }
}

nonisolated enum BackgroundFill: Codable, Equatable, Sendable {
    /// An index into `BackgroundPresets.gradients`. An index out of range draws preset 0.
    case gradient(Int)
    case solid(RGBA)
    /// The wallpaper of the display concerned. It arrives as the compositor's `fillImage`.
    case desktopPicture
    /// The one stored custom image. It arrives as the compositor's `fillImage`.
    case customImage
}

nonisolated enum BackgroundAspect: String, Codable, CaseIterable, Sendable {
    case auto, square, fourThree, threeTwo, sixteenTen, sixteenNine

    var title: String {
        switch self {
        case .auto: "Auto"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenTen: "16:10"
        case .sixteenNine: "16:9"
        }
    }

    /// Width over height, nil for `.auto`.
    var ratio: CGFloat? {
        guard let terms else { return nil }
        return CGFloat(terms.width) / CGFloat(terms.height)
    }

    /// The ratio as whole numbers, so the layout can round without floating-point drift.
    var terms: (width: Int, height: Int)? {
        switch self {
        case .auto: nil
        case .square: (1, 1)
        case .fourThree: (4, 3)
        case .threeTwo: (3, 2)
        case .sixteenTen: (16, 10)
        case .sixteenNine: (16, 9)
        }
    }
}
