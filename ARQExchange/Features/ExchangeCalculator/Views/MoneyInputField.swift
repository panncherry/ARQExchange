import SwiftUI

struct MoneyInputField: View {
    let formattedAmount: String
    let keyboardDigits: String
    let accessibilityPrefix: String
    let focusBinding: FocusState<AmountField?>.Binding
    let focusValue: AmountField
    let onKeyboardChange: (String) -> String

    @State private var draftText = ""

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(formattedAmount)
                .font(AppFontDesign.bodyBold)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .monospacedDigit()
                .accessibilityIdentifier("\(accessibilityPrefix)AmountLabel")
                .transaction { transaction in
                    transaction.animation = nil
                }

            TextField("", text: Binding(
                get: { draftText },
                set: { newValue in
                    draftText = onKeyboardChange(newValue)
                }
            ))
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
            .font(AppFontDesign.bodyBold)
            .foregroundStyle(.clear)
            .tint(.blue)
            .focused(focusBinding, equals: focusValue)
            .accessibilityIdentifier("\(accessibilityPrefix)AmountField")
        }
        .onAppear {
            draftText = keyboardDigits
        }
        .onChange(of: keyboardDigits) { _, newValue in
            if draftText != newValue {
                draftText = newValue
            }
        }
    }
}

#if DEBUG
#Preview("Money Input") {
    PreviewScreen {
        PreviewFocusHost(initialFocus: .top) { focusedField in
            MoneyInputField(
                formattedAmount: "$100.00",
                keyboardDigits: "10000",
                accessibilityPrefix: "top",
                focusBinding: focusedField,
                focusValue: .top,
                onKeyboardChange: { $0 }
            )
            .padding(20)
        }
    }
}
#endif
