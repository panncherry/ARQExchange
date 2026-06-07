import SwiftUI

struct CurrencySwapButton: View {
    let action: () -> Void

    static let buttonSize: CGFloat = 24
    static let borderWidth: CGFloat = 2
    static var outerDiameter: CGFloat { buttonSize + borderWidth * 6 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AppTheme.outerRing.opacity(0.9))
                    .frame(width: Self.outerDiameter, height: Self.outerDiameter)
                    .appScreenDropShadow()

                Circle()
                    .fill(AppTheme.accentGreen)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)

                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapButton")
        .accessibilityLabel("Swap currencies")
    }
}

#if DEBUG
#Preview("Swap Button") {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        CurrencySwapButton(action: {})
    }
}
#endif
