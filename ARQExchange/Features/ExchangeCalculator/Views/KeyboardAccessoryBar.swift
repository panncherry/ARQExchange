import SwiftUI

/// Bar shown directly above the number pad when an amount field is focused.
struct KeyboardAccessoryBar: View {
    var limitWarning: String? = nil
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let limitWarning {
                Text(limitWarning)
                    .font(AppFontDesign.footnote.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("amountLimitWarning")
            } else {
                Spacer(minLength: 0)
            }

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGreen)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keyboardDoneButton")
            .accessibilityLabel("Done")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

#if DEBUG
#Preview("Keyboard Accessory") {
    PreviewScreen {
        VStack {
            Spacer()
            KeyboardAccessoryBar(onDone: {})
        }
    }
}

#Preview("Keyboard Accessory With Limit") {
    PreviewScreen {
        VStack {
            Spacer()
            KeyboardAccessoryBar(
                limitWarning: ExchangeCalculatorViewModel.maximumAmountReachedMessage,
                onDone: {}
            )
        }
    }
}
#endif
