import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Deep Tide brand colours (Captylo's `VTColor`, the ones Tidewatch uses).
enum BrandColor {
    static let abyss = Color(hex: 0x10272C)
    static let petrol = Color(hex: 0x214A52)
    static let tide = Color(hex: 0x2F8F88)
}
