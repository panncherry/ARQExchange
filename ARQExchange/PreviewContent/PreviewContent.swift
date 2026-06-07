#if DEBUG
import SwiftUI

enum PreviewContent {
    @MainActor static var mxn: AppCurrency { currency(code: "MXN") }
    @MainActor static var cop: AppCurrency { currency(code: "COP") }

    @MainActor
    static func calculatorViewModel(
        topMinorUnits: Int64 = 100_00,
        bottomCurrency: AppCurrency? = nil
    ) -> ExchangeCalculatorViewModel {
        ExchangeCalculatorViewModel.preview(
            topMinorUnits: topMinorUnits,
            bottomCurrency: bottomCurrency ?? mxn
        )
    }

    @MainActor
    private static func currency(code: String) -> AppCurrency {
        SupportedCurrencies.pickerCurrencies.first { $0.code == code }!
    }
}

struct PreviewScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            content
        }
    }
}

struct PreviewFocusHost<Content: View>: View {
    let initialFocus: AmountField?
    let content: (FocusState<AmountField?>.Binding) -> Content
    @FocusState private var focusedField: AmountField?

    init(
        initialFocus: AmountField? = nil,
        @ViewBuilder content: @escaping (FocusState<AmountField?>.Binding) -> Content
    ) {
        self.initialFocus = initialFocus
        self.content = content
    }

    var body: some View {
        content($focusedField)
            .onAppear {
                focusedField = initialFocus
            }
    }
}
#endif
