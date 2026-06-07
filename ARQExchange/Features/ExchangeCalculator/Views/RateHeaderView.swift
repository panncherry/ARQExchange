import SwiftUI

/// Fixed-height rate block so loading, refresh, and background updates do not shift layout.
struct RateHeaderView: View {
    static let slotHeight: CGFloat = 72

    let rateDescription: String
    let rateFreshnessLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rateDescription)
                .font(AppFontDesign.bodySemiBold)
                .foregroundStyle(AppTheme.accentGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityIdentifier("rateDescription")

            Text(rateFreshnessLabel)
                .font(AppFontDesign.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .accessibilityIdentifier("rateFreshnessLabel")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.slotHeight, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

#if DEBUG
#Preview("Rate Header") {
    PreviewScreen {
        RateHeaderView(
            rateDescription: "1 USDc = 18.41 MXN",
            rateFreshnessLabel: "Live rate"
        )
        .padding(20)
    }
}

#Preview("Updated Rate Header") {
    PreviewScreen {
        RateHeaderView(
            rateDescription: "1 USDc = 3,832.42 COP",
            rateFreshnessLabel: "Updated 2 min ago"
        )
        .padding(20)
    }
}
#endif
