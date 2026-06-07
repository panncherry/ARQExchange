import SwiftUI

enum AppShadows {
    /// Figma: Screen Drop Shadow — x: 0, y: 4, blur: 10, spread: 0, #000000 10%
    static let screenDropColor = Color.black.opacity(0.1)
    static let screenDropRadius: CGFloat = 10
    static let screenDropY: CGFloat = 4
}

enum AppTheme {
    static let accentGreen = AppColors.contentBrand
    static let background = AppColors.backgroundPrimary
    static let outerRing = AppColors.borderColor
    static let cardBackground = AppColors.backgroundSecondary
    static let primaryText = AppColors.contentPrimary
    static let secondaryText = Color.secondary
    static let divider = AppColors.borderOnSecondary
    static let onSecondaryBackground = AppColors.backgroundOnSecondary
}

extension View {
    /// Applies the Figma `Screen Drop Shadow` token used on surfaces over `bg-primary-new`.
    func appScreenDropShadow() -> some View {
        shadow(
            color: AppShadows.screenDropColor,
            radius: AppShadows.screenDropRadius,
            x: 0,
            y: AppShadows.screenDropY
        )
    }
}
