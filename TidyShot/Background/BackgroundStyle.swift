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

    init(fill: BackgroundFill = .gradient(0), padding: Double = 48, cornerRadius: Double = 12,
         shadow: Bool = true, aspect: BackgroundAspect = .auto) {
        self.fill = fill
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.aspect = aspect
    }

    private enum CodingKeys: String, CodingKey {
        case fill, padding, cornerRadius, shadow, aspect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fill = try container.decodeIfPresent(BackgroundFill.self, forKey: .fill) ?? .gradient(0)
        padding = try container.decodeIfPresent(Double.self, forKey: .padding) ?? 48
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 12
        shadow = try container.decodeIfPresent(Bool.self, forKey: .shadow) ?? true
        aspect = try container.decodeIfPresent(BackgroundAspect.self, forKey: .aspect) ?? .auto
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
