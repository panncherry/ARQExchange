import SwiftUI

/// Top and bottom currency rows with the swap control between them.
struct ExchangeInputSection: View {
    @Bindable var viewModel: ExchangeCalculatorViewModel
    var focusedField: FocusState<AmountField?>.Binding
    var onSwapRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 16) {
                ExchangeInputRow(field: .top, viewModel: viewModel, focusedField: focusedField)

                VStack(alignment: .trailing, spacing: 4) {
                    ExchangeInputRow(field: .bottom, viewModel: viewModel, focusedField: focusedField)

                    if focusedField.wrappedValue == nil, let warning = viewModel.amountLimitWarning {
                        Text(warning)
                            .font(AppFontDesign.footnote.weight(.semibold))
                            .foregroundStyle(Color.orange)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 16)
                            .accessibilityIdentifier("amountLimitWarning")
                    }
                }
            }
            .overlay {
                CurrencySwapButton(action: onSwapRequested)
                    .allowsHitTesting(!viewModel.isSwapInProgress)
                    .opacity(viewModel.isSwapInProgress ? 0.5 : 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("currencyInputCard")
    }
}

#if DEBUG
#Preview("Input Section") {
    PreviewScreen {
        PreviewFocusHost { focusedField in
            ExchangeInputSection(
                viewModel: PreviewContent.calculatorViewModel(topMinorUnits: 100_00),
                focusedField: focusedField,
                onSwapRequested: {}
            )
            .padding(20)
        }
    }
}

#Preview("Focused Section") {
    PreviewScreen {
        PreviewFocusHost(initialFocus: .top) { focusedField in
            ExchangeInputSection(
                viewModel: PreviewContent.calculatorViewModel(topMinorUnits: 250_00),
                focusedField: focusedField,
                onSwapRequested: {}
            )
            .padding(20)
        }
    }
}
#endif
