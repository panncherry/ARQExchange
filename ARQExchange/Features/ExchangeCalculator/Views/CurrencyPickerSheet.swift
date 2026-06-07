import SwiftUI

struct CurrencyPickerSheet: View {
    let isCurrencySelected: (AppCurrency) -> Bool
    let onSelect: (AppCurrency) -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let currencies = SupportedCurrencies.pickerCurrencies

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 16)

            currencyList
                .padding(.top, 24)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.background.ignoresSafeArea())
        .accessibilityIdentifier("currencyPickerSheet")
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Choose currency")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 12)

            Button {
                onDismiss()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("closeCurrencyPicker")
            .accessibilityLabel("Close")
        }
    }

    private var currencyList: some View {
        VStack(spacing: 0) {
            ForEach(currencies) { currency in
                currencyRow(currency)
            }
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .appScreenDropShadow()
    }

    private func currencyRow(_ currency: AppCurrency) -> some View {
        Button {
            onSelect(currency)
        } label: {
            HStack(spacing: 16) {
                Text(currency.flagEmoji)
                    .font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(AppTheme.outerRing.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                Text(currency.code)
                    .font(AppFontDesign.body)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: 12)

                selectionIndicator(isSelected: isCurrencySelected(currency))
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("currencyOption_\(currency.code)")
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        if isSelected {
            Circle()
                .fill(AppTheme.accentGreen)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Selected")
        } else {
            Circle()
                .stroke(AppTheme.divider, lineWidth: 2)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Not selected")
        }
    }
}

#if DEBUG
#Preview("Currency Picker") {
    CurrencyPickerSheet(
        isCurrencySelected: { $0.code == PreviewContent.mxn.code },
        onSelect: { _ in },
        onDismiss: {}
    )
}
#endif
