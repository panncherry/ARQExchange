import SwiftUI

enum AppColors {
    static let backgroundPrimary = Color(hex: 0xF8F8F8)
    static let backgroundSecondary = Color(hex: 0xFFFFFF)
    static let backgroundOnSecondary = Color(hex: 0xF4F4F4)

    static let contentPrimary = Color(hex: 0x2C2C2E)
    static let contentBrand = Color(hex: 0x22D081)

    static let borderOnSecondary = Color(hex: 0xD4D4D4)
    static let borderColor = Color(hex: 0xDFDFDF)
}

private extension Color {
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
