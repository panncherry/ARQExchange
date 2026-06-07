import SwiftUI

/// Root calculator screen that binds the observable view model to SwiftUI focus,
/// sheet, refresh, and lifecycle tasks.
struct ExchangeCalculatorScreen: View {
    /// Task identity used to start/cancel screen refresh work through SwiftUI's `.task(id:)`.
    private enum CalculatorSession: Equatable {
        case initial
        case foregroundResume
        case retry(Int)
    }

    private static let loadingRateDescription = "Exchange rate"
    private static let loadingFreshnessLabel = "Loading latest rate"

    @State private var viewModel: ExchangeCalculatorViewModel
    @FocusState private var focusedAmountField: AmountField?
    @Environment(\.scenePhase) private var scenePhase
    @State private var calculatorSession: CalculatorSession?
    @State private var retryGeneration = 0
    @State private var currencySelectionGeneration = 0
    @State private var swapGeneration = 0
    @State private var selectedCurrency: AppCurrency?

    init(viewModel: ExchangeCalculatorViewModel = AppDependencies.makeExchangeCalculatorViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .background(AppTheme.background)
                .navigationTitle("Exchange calculator")
                .navigationBarTitleDisplayMode(.large)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            if viewModel.screenState.isInteractive {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("appReady")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedAmountField != nil, showsKeyboardAccessory {
                KeyboardAccessoryBar(
                    limitWarning: viewModel.amountLimitWarning,
                    onDone: { focusedAmountField = nil }
                )
            }
        }
        .task(id: calculatorSession) {
            guard let session = calculatorSession else { return }

            switch session {
            case .initial:
                await viewModel.activateScreen()
            case .foregroundResume:
                await viewModel.refreshOnReturnToForeground()
            case .retry:
                await viewModel.retryLoading()
            }

            guard viewModel.canPollIndicativeRates else { return }
            await viewModel.runIndicativeRefreshLoop()
        }
        .task(id: currencySelectionGeneration) {
            guard currencySelectionGeneration > 0, let currency = selectedCurrency else { return }
            await viewModel.selectCurrency(currency)
        }
        .task(id: swapGeneration) {
            guard swapGeneration > 0 else { return }
            await viewModel.swapCurrencies()
        }
        .onAppear {
            if calculatorSession == nil {
                calculatorSession = .initial
            }
        }
        .onDisappear {
            calculatorSession = nil
            viewModel.deactivateScreen()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                calculatorSession = nil
            case .active where oldPhase == .background:
                calculatorSession = .foregroundResume
            default:
                break
            }
        }
        .onChange(of: viewModel.screenState) { _, newState in
            if case .failed = newState {
                focusedAmountField = nil
            }
        }
        .sheet(isPresented: $viewModel.isCurrencyPickerPresented) {
            CurrencyPickerSheet(
                isCurrencySelected: viewModel.isCurrencySelected,
                onSelect: { currency in
                    selectedCurrency = currency
                    currencySelectionGeneration += 1
                },
                onDismiss: { viewModel.dismissCurrencyPicker() }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AppTheme.background)
            .presentationCornerRadius(28)
        }
    }

    private var showsKeyboardAccessory: Bool {
        switch viewModel.screenState {
        case .failed:
            false
        case .loading, .ready:
            true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screenState {
        case .failed(let message):
            failedContent(message: message)

        case .loading, .ready:
            calculatorContent
        }
    }

    /// Main calculator content shown while rates are loading or ready.
    private var calculatorContent: some View {
        ZStack {
            AppTheme.background
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissKeyboard)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    header

                    if let refreshFailureMessage = viewModel.refreshFailureMessage {
                        Text(refreshFailureMessage)
                            .font(AppFontDesign.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("refreshFailureMessage")
                    }

                    ExchangeInputSection(
                        viewModel: viewModel,
                        focusedField: $focusedAmountField,
                        onSwapRequested: { swapGeneration += 1 }
                    )
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissKeyboard)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await viewModel.pullToRefresh()
            }
        }
    }

    private func dismissKeyboard() {
        focusedAmountField = nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            rateHeaderSlot
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(nil, value: viewModel.screenState)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private var rateHeaderSlot: some View {
        switch viewModel.screenState {
        case .failed:
            EmptyView()

        case .loading:
            RateHeaderView(
                rateDescription: Self.loadingRateDescription,
                rateFreshnessLabel: Self.loadingFreshnessLabel
            )
            .redacted(reason: .placeholder)
            .overlay(alignment: .topLeading) {
                ProgressView()
                    .controlSize(.small)
            }

        case .ready(let rateDescription, let rateFreshnessLabel):
            RateHeaderView(
                rateDescription: rateDescription,
                rateFreshnessLabel: rateFreshnessLabel
            )
        }
    }

    /// Scrollable full-screen initial-load failure state for small devices and Dynamic Type.
    private func failedContent(message: String) -> some View {
        GeometryReader { proxy in
            ScrollView {
                failedErrorView(message: message)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 40)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func failedErrorView(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Unable to Load Rates")
                    .font(AppFontDesign.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(AppFontDesign.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("errorMessage")
            }

            Button {
                retryGeneration += 1
                calculatorSession = .retry(retryGeneration)
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(AppFontDesign.bodySemiBold)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accentGreen)
            .accessibilityIdentifier("retryButton")
        }
    }
}

#if DEBUG
#Preview("Ready") {
    ExchangeCalculatorScreen(viewModel: PreviewContent.calculatorViewModel())
}

#Preview("Large Amount") {
    ExchangeCalculatorScreen(
        viewModel: PreviewContent.calculatorViewModel(
            topMinorUnits: 1_250_000,
            bottomCurrency: PreviewContent.cop
        )
    )
}
#endif
