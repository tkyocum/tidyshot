nonisolated struct GradientPreset: Equatable, Sendable {
    let name: String
    let first: RGBA
    let second: RGBA

    fileprivate init(_ name: String, _ first: UInt32, _ second: UInt32) {
        self.name = name
        self.first = RGBA(hex: first)
        self.second = RGBA(hex: second)
    }
}

nonisolated enum BackgroundPresets {
    /// Two-stop linear gradients, drawn from the top-left corner (first) to the bottom-right
    /// corner (second) of the whole background.
    static let gradients: [GradientPreset] = [
        GradientPreset("Sunset", 0xFF7A59, 0x7B4DFF),
        GradientPreset("Ocean", 0x1FA2FF, 0xA6FFCB),
        GradientPreset("Grape", 0x8E2DE2, 0x4A00E0),
        GradientPreset("Peach", 0xFFD3A5, 0xFD6585),
        GradientPreset("Mint", 0x43E97B, 0x38F9D7),
        GradientPreset("Midnight", 0x232526, 0x414345),
        GradientPreset("Sky", 0xA1C4FD, 0xC2E9FB),
        GradientPreset("Flamingo", 0xF857A6, 0xFF5858),
        GradientPreset("Forest", 0x134E5E, 0x71B280),
        GradientPreset("Lemon", 0xF9F586, 0x96FBC4),
        GradientPreset("Slate", 0x8E9EAB, 0xEEF2F3),
        GradientPreset("Berry", 0xC471F5, 0xFA71CD),
    ]
}
