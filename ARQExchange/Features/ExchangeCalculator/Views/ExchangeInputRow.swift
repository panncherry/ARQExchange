import SwiftUI

/// A single currency + amount row in the exchange calculator.
struct ExchangeInputRow: View {
    let field: AmountField
    @Bindable var viewModel: ExchangeCalculatorViewModel
    var focusedField: FocusState<AmountField?>.Binding

    private var currency: AppCurrency {
        viewModel.currency(for: field)
    }

    private var showsPicker: Bool {
        viewModel.isFieldSelectable(field)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(currency.flagEmoji)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(AppTheme.onSecondaryBackground)
                .clipShape(Circle())

            currencySelector

            Spacer(minLength: 8)

            MoneyInputField(
                formattedAmount: viewModel.formattedAmount(for: field),
                keyboardDigits: viewModel.keyboardDigits(for: field),
                accessibilityPrefix: field.accessibilityPrefix,
                focusBinding: focusedField,
                focusValue: field,
                onKeyboardChange: { viewModel.updateKeyboardInput($0, for: field) }
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cardBackground)
        }
        .appScreenDropShadow()
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            focusedField.wrappedValue = field
            viewModel.selectField(field)
        }
        .id("\(field.accessibilityPrefix)-\(currency.code)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(field.accessibilityPrefix)InputRow")
    }

    @ViewBuilder
    private var currencySelector: some View {
        let label = HStack(spacing: 8) {
            Text(currency.code)
                .font(AppFontDesign.bodySemiBold)
                .foregroundStyle(AppTheme.primaryText)

            if showsPicker {
                Image(systemName: "chevron.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
            }
        }

        if showsPicker {
            Button(action: viewModel.presentCurrencyPicker) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(field.accessibilityPrefix)CurrencyButton")
        } else {
            label
                .accessibilityIdentifier("\(field.accessibilityPrefix)CurrencyButton")
        }
    }
}

#if DEBUG
#Preview("Send Row") {
    PreviewScreen {
        PreviewFocusHost { focusedField in
            ExchangeInputRow(
                field: .top,
                viewModel: PreviewContent.calculatorViewModel(topMinorUnits: 1_00_00),
                focusedField: focusedField
            )
            .padding(20)
        }
    }
}

#Preview("Receive Row") {
    PreviewScreen {
        PreviewFocusHost(initialFocus: .bottom) { focusedField in
            ExchangeInputRow(
                field: .bottom,
                viewModel: PreviewContent.calculatorViewModel(topMinorUnits: 1_00_00),
                focusedField: focusedField
            )
            .padding(20)
        }
    }
}
#endif
