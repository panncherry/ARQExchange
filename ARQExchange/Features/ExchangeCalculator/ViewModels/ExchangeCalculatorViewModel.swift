import Foundation
import Observation
import SwiftUI

/// Main state machine for the exchange calculator screen.
///
/// The view model owns currency selection, amount derivation, rate refresh coalescing,
/// stale-result protection, and user-safe error presentation. It is `@MainActor` because
/// SwiftUI observes it directly and all mutations feed visible screen state.
@MainActor
@Observable
final class ExchangeCalculatorViewModel {
    private static let rateLoadFailureMessage = "Unable to load exchange rates. Check your connection and try again."

    private(set) var topCurrency: AppCurrency = SupportedCurrencies.usdc
    private(set) var bottomCurrency: AppCurrency = SupportedCurrencies.defaultQuoteCurrency
    private(set) var activeField: AmountField = .top

    private(set) var topAmount = MoneyInputViewModel(currency: SupportedCurrencies.usdc)
    private(set) var bottomAmount = MoneyInputViewModel(
        currency: SupportedCurrencies.defaultQuoteCurrency
    )

    private(set) var screenState: ExchangeCalculatorScreenState = .loading
    var isCurrencyPickerPresented = false

    private var currentRate: ExchangeRate?
    private let repository: ExchangeRateRepositoryProtocol
    private var isRatesRefreshInFlight = false
    private var ratesRefreshWaiters: [CheckedContinuation<RatesRefreshOutcome, Never>] = []
    private var ratesRefreshRequest: RatesRefreshRequest?
    private var ratesRefreshToken: UInt = 0
    private var coalescedPresentation: RatesRefreshPresentation = .silent
    private var coalescedPolicy: RateRefreshPolicy = .useCacheIfFresh
    private var coalescedApplyToScreen = false
    private var layoutGeneration: UInt = 0
    private var showsRejectedAmountWarning = false
    private(set) var isSwapInProgress = false
    private(set) var refreshFailureMessage: String?

    init(repository: ExchangeRateRepositoryProtocol) {
        self.repository = repository
    }

    var topFormattedAmount: String { topAmount.formattedAmount }
    var bottomFormattedAmount: String { bottomAmount.formattedAmount }

    /// Performs the initial visible refresh when the calculator appears.
    func activateScreen() async {
        await refreshIndicativeRates(policy: .forceRefresh, showLoading: true)
    }

    /// Invalidates in-flight UI refresh results when the screen leaves the foreground.
    func deactivateScreen() {
        ratesRefreshToken &+= 1
        cancelRatesRefreshWaiters(returning: .superseded)
    }

    func refreshOnReturnToForeground() async {
        await refreshIndicativeRates(policy: .forceRefresh, showLoading: false)
    }

    /// Polls for fresh indicative rates while the hosting `.task` remains active.
    func runIndicativeRefreshLoop() async {
        let interval = ARQAPIConfiguration.indicativeRateRefreshInterval
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            _ = await scheduleRatesRefresh(policy: .useCacheIfFresh, presentation: .silent)
        }
    }

    func retryLoading() async {
        await refreshIndicativeRates(policy: .forceRefresh, showLoading: true)
    }

    func pullToRefresh() async {
        await scheduleRatesRefresh(policy: .forceRefresh, presentation: .visible)
    }

    func selectField(_ field: AmountField) {
        activeField = field
        recalculateDerivedField()
    }

    func currency(for field: AmountField) -> AppCurrency {
        field == .top ? topCurrency : bottomCurrency
    }

    func formattedAmount(for field: AmountField) -> String {
        field == .top ? topFormattedAmount : bottomFormattedAmount
    }

    func keyboardDigits(for field: AmountField) -> String {
        field == .top ? topKeyboardDigits : bottomKeyboardDigits
    }

    func updateKeyboardInput(_ text: String, for field: AmountField) -> String {
        switch field {
        case .top: return updateTopKeyboardInput(text)
        case .bottom: return updateBottomKeyboardInput(text)
        }
    }

    var topKeyboardDigits: String { topAmount.keyboardDigits }
    var bottomKeyboardDigits: String { bottomAmount.keyboardDigits }

    @discardableResult
    func updateTopKeyboardInput(_ text: String) -> String {
        if activeField != .top { selectField(.top) }
        return applyKeyboardInput(
            text,
            to: topAmount,
            from: topCurrency,
            to: bottomAmount,
            target: bottomCurrency
        )
    }

    @discardableResult
    func updateBottomKeyboardInput(_ text: String) -> String {
        if activeField != .bottom { selectField(.bottom) }
        return applyKeyboardInput(
            text,
            to: bottomAmount,
            from: bottomCurrency,
            to: topAmount,
            target: topCurrency
        )
    }

    /// Bumped when keyboard input is rejected so limit warnings refresh without a net amount change.
    private(set) var inputValidationTick = 0

    @discardableResult
    private func applyKeyboardInput(
        _ text: String,
        to activeAmount: MoneyInputViewModel,
        from sourceCurrency: AppCurrency,
        to derivedAmount: MoneyInputViewModel,
        target targetCurrency: AppCurrency
    ) -> String {
        let previousMinorUnits = activeAmount.minorUnits

        guard activeAmount.applyKeyboardDigits(text) else {
            noteInputRejectedAtLimit()
            return activeAmount.keyboardDigits
        }

        showsRejectedAmountWarning = false

        if exceedsDerivedLimit(
            sourceAmount: activeAmount.decimalAmount,
            from: sourceCurrency,
            to: targetCurrency
        ) {
            activeAmount.restoreMinorUnits(previousMinorUnits)
            noteInputRejectedAtLimit()
            return activeAmount.keyboardDigits
        }

        recalculateDerivedField()
        return activeAmount.keyboardDigits
    }

    private func noteInputRejectedAtLimit() {
        showsRejectedAmountWarning = true
        inputValidationTick &+= 1
    }

    private func clearLimitWarningState() {
        showsRejectedAmountWarning = false
        inputValidationTick &+= 1
    }

    /// Swaps the row positions and refreshes the quote book for the new direction.
    func swapCurrencies() async {
        guard !isSwapInProgress else { return }
        isSwapInProgress = true
        defer { isSwapInProgress = false }

        layoutGeneration &+= 1
        clearLimitWarningState()

        let newTopCurrency = bottomCurrency
        let newBottomCurrency = topCurrency
        let newTopMinorUnits = bottomAmount.minorUnits
        let newBottomMinorUnits = topAmount.minorUnits

        topCurrency = newTopCurrency
        bottomCurrency = newBottomCurrency
        topAmount = MoneyInputViewModel(currency: topCurrency, minorUnits: newTopMinorUnits)
        bottomAmount = MoneyInputViewModel(currency: bottomCurrency, minorUnits: newBottomMinorUnits)
        applyReadyState()
        await scheduleRatesRefresh(policy: .forceRefresh, presentation: .visible)
    }

    func presentCurrencyPicker() {
        isCurrencyPickerPresented = true
    }

    func dismissCurrencyPicker() {
        isCurrencyPickerPresented = false
    }

    /// Selects a new non-USDc currency after fetching its rate.
    ///
    /// The method captures the current layout generation so stale selections cannot apply
    /// to the wrong row if the user swaps while the fetch is in flight.
    func selectCurrency(_ currency: AppCurrency) async {
        guard currency.isSelectableInPicker else { return }

        let selectionLayoutGeneration = layoutGeneration
        let targetField: AmountField = topCurrency.isUSDC ? .bottom : .top
        let currentCurrency = targetField == .top ? topCurrency : bottomCurrency
        guard currency.code != currentCurrency.code else {
            isCurrencyPickerPresented = false
            return
        }

        isCurrencyPickerPresented = false
        clearLimitWarningState()

        let outcome = await scheduleRatesRefresh(
            policy: .forceRefresh,
            presentation: .visible,
            fetchQuote: currency,
            applyToScreen: false
        )

        guard selectionLayoutGeneration == layoutGeneration else { return }

        switch outcome {
        case .success(let rate):
            applyCurrencySelection(currency, rate: rate, targetField: targetField)
        case .failure:
            applyReadyState()
        case .cancelled, .superseded:
            break
        }
    }

    func isFieldSelectable(_ field: AmountField) -> Bool {
        selectableCurrency(for: field) != nil
    }

    func isCurrencySelected(_ currency: AppCurrency) -> Bool {
        topCurrency.code == currency.code || bottomCurrency.code == currency.code
    }

    func selectableCurrency(for field: AmountField) -> AppCurrency? {
        let currency = field == .top ? topCurrency : bottomCurrency
        return currency.isSelectableInPicker ? currency : nil
    }

    private var quoteCurrency: AppCurrency {
        topCurrency.isUSDC ? bottomCurrency : topCurrency
    }

    private enum RatesRefreshPresentation {
        case silent
        case visible
        case loading

        func merged(with other: Self) -> Self {
            switch (self, other) {
            case (.loading, _), (_, .loading): .loading
            case (.visible, _), (_, .visible): .visible
            default: .silent
            }
        }
    }

    private enum RatesRefreshOutcome {
        case success(ExchangeRate)
        case failure(Error)
        case cancelled
        case superseded
    }

    private struct RatesRefreshRequest {
        let quote: AppCurrency
        let policy: RateRefreshPolicy
        let applyToScreen: Bool
    }

    private func refreshIndicativeRates(policy: RateRefreshPolicy, showLoading: Bool) async {
        _ = await scheduleRatesRefresh(
            policy: policy,
            presentation: showLoading ? .loading : .silent
        )
    }

    /// Schedules a rate refresh, coalescing compatible overlapping requests.
    ///
    /// A newer request can reuse an in-flight refresh only when the active request already
    /// satisfies its quote, refresh policy, and screen-application requirements. Otherwise
    /// this method waits for the active refresh to settle and immediately starts another one.
    @discardableResult
    private func scheduleRatesRefresh(
        policy: RateRefreshPolicy,
        presentation: RatesRefreshPresentation,
        fetchQuote: AppCurrency? = nil,
        applyToScreen: Bool = true
    ) async -> RatesRefreshOutcome {
        coalescedPresentation = coalescedPresentation.merged(with: presentation)
        coalescedPolicy = coalescedPolicy.merged(with: policy)
        coalescedApplyToScreen = coalescedApplyToScreen || applyToScreen

        while true {
            let desiredQuote = fetchQuote ?? quoteCurrency

            if isRatesRefreshInFlight {
                let existingRequest = ratesRefreshRequest
                let outcome = await withCheckedContinuation { continuation in
                    ratesRefreshWaiters.append(continuation)
                }
                if shouldRunAnotherRefresh(
                    after: outcome,
                    fetchQuote: fetchQuote,
                    desiredQuote: desiredQuote,
                    requestedPolicy: policy,
                    requestedApplyToScreen: applyToScreen,
                    existingRequest: existingRequest
                ) {
                    continue
                }
                resetCoalescedRefreshState()
                return outcome
            }

            ratesRefreshToken &+= 1
            let token = ratesRefreshToken
            let quote = desiredQuote
            let effectivePresentation = coalescedPresentation
            let effectivePolicy = coalescedPolicy
            let effectiveApplyToScreen = coalescedApplyToScreen
            resetCoalescedRefreshState()
            ratesRefreshRequest = RatesRefreshRequest(
                quote: quote,
                policy: effectivePolicy,
                applyToScreen: effectiveApplyToScreen
            )
            isRatesRefreshInFlight = true
            let outcome = await runRatesRefresh(
                quote: quote,
                policy: effectivePolicy,
                presentation: effectivePresentation,
                token: token,
                applyToScreen: effectiveApplyToScreen,
                isSelectionFetch: fetchQuote != nil
            )
            isRatesRefreshInFlight = false
            ratesRefreshRequest = nil
            resumeRatesRefreshWaiters(with: outcome)
            return outcome
        }
    }

    private func resumeRatesRefreshWaiters(with outcome: RatesRefreshOutcome) {
        let waiters = ratesRefreshWaiters
        ratesRefreshWaiters = []
        for waiter in waiters {
            waiter.resume(returning: outcome)
        }
    }

    private func cancelRatesRefreshWaiters(returning outcome: RatesRefreshOutcome) {
        isRatesRefreshInFlight = false
        ratesRefreshRequest = nil
        let waiters = ratesRefreshWaiters
        ratesRefreshWaiters = []
        for waiter in waiters {
            waiter.resume(returning: outcome)
        }
    }

    /// Executes the repository refresh and applies the result only if it still matches current state.
    private func runRatesRefresh(
        quote: AppCurrency,
        policy: RateRefreshPolicy,
        presentation: RatesRefreshPresentation,
        token: UInt,
        applyToScreen: Bool,
        isSelectionFetch: Bool
    ) async -> RatesRefreshOutcome {
        guard token == ratesRefreshToken else { return .superseded }

        if presentation == .loading {
            screenState = .loading
        }

        do {
            try Task.checkCancellation()
            let rate = try await repository.refreshExchangeRate(for: quote, policy: policy)

            guard isResultStillValid(token: token, quote: quote, isSelectionFetch: isSelectionFetch) else {
                return .superseded
            }

            if applyToScreen {
                refreshFailureMessage = nil
                applyFetchedRate(rate)
            }

            return .success(rate)
        } catch is CancellationError {
            return .cancelled
        } catch {
            guard isResultStillValid(token: token, quote: quote, isSelectionFetch: isSelectionFetch) else {
                return .superseded
            }

            if applyToScreen {
                handleRefreshFailure(error)
            }

            return .failure(error)
        }
    }

    private func shouldRunAnotherRefresh(
        after outcome: RatesRefreshOutcome,
        fetchQuote: AppCurrency?,
        desiredQuote: AppCurrency,
        requestedPolicy: RateRefreshPolicy,
        requestedApplyToScreen: Bool,
        existingRequest: RatesRefreshRequest?
    ) -> Bool {
        guard let existingRequest else { return true }

        let expectedCode = (fetchQuote ?? desiredQuote).currencyCode
        guard existingRequest.quote.currencyCode == expectedCode else { return true }

        if requestedPolicy == .forceRefresh, existingRequest.policy != .forceRefresh {
            return true
        }

        if requestedApplyToScreen, !existingRequest.applyToScreen {
            return true
        }

        switch outcome {
        case .success(let rate):
            return rate.currency.currencyCode != expectedCode
        case .failure, .cancelled, .superseded:
            return fetchQuote != nil
        }
    }

    private func resetCoalescedRefreshState() {
        coalescedPresentation = .silent
        coalescedPolicy = .useCacheIfFresh
        coalescedApplyToScreen = false
    }

    private func isResultStillValid(
        token: UInt,
        quote: AppCurrency,
        isSelectionFetch: Bool
    ) -> Bool {
        guard token == ratesRefreshToken else { return false }
        if isSelectionFetch {
            return true
        }
        return quote.currencyCode == quoteCurrency.currencyCode
    }

    private func applyCurrencySelection(
        _ currency: AppCurrency,
        rate: ExchangeRate,
        targetField: AmountField
    ) {
        clearLimitWarningState()

        switch targetField {
        case .top:
            let preservedMinorUnits = topAmount.minorUnits
            topCurrency = currency
            topAmount = MoneyInputViewModel(currency: currency, minorUnits: preservedMinorUnits)
        case .bottom:
            let preservedMinorUnits = bottomAmount.minorUnits
            bottomCurrency = currency
            bottomAmount = MoneyInputViewModel(currency: currency, minorUnits: preservedMinorUnits)
        }

        applyRateUpdate(rate, recalculateAmounts: true)
    }

    private func handleRefreshFailure(_ error: Error) {
        let message = userFacingMessage(
            for: error,
            fallback: Self.rateLoadFailureMessage
        )

        if currentRate == nil {
            refreshFailureMessage = nil
            screenState = .failed(message: message)
        } else {
            refreshFailureMessage = message
            applyReadyState()
        }
    }

    private func applyFetchedRate(_ rate: ExchangeRate) {
        applyRateUpdate(rate, recalculateAmounts: true)
    }

    private func applyReadyState() {
        guard let currentRate else {
            screenState = .failed(message: Self.rateLoadFailureMessage)
            return
        }

        applyRateUpdate(currentRate, recalculateAmounts: false)
    }

    /// Updates header, amounts, and freshness without implicit SwiftUI animations.
    /// Applies a fresh rate to header state and derived amount state in one transaction.
    private func applyRateUpdate(
        _ rate: ExchangeRate,
        recalculateAmounts: Bool
    ) {
        let description = makeRateDescription(for: rate)
        let freshness = RateFreshnessFormatter.indicativeLabel(updatedAt: rate.updatedAt)
        let rateValuesChanged = hasRateValuesChanged(from: currentRate, to: rate)
        let headerNeedsUpdate = headerNeedsUpdate(
            description: description,
            freshness: freshness
        )
        let amountsNeedUpdate = recalculateAmounts && rateValuesChanged && hasEnteredAmount

        guard rateValuesChanged || headerNeedsUpdate || amountsNeedUpdate else { return }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            currentRate = rate

            if amountsNeedUpdate {
                recalculateDerivedField()
            }

            screenState = .ready(
                rateDescription: description,
                rateFreshnessLabel: freshness
            )
        }
    }

    private func headerNeedsUpdate(
        description: String,
        freshness: String
    ) -> Bool {
        switch screenState {
        case .loading, .failed:
            return true
        case .ready(let currentDescription, let currentFreshness):
            return currentDescription != description
                || currentFreshness != freshness
        }
    }

    private func hasRateValuesChanged(from oldRate: ExchangeRate?, to newRate: ExchangeRate) -> Bool {
        guard let oldRate else { return true }
        return oldRate.ask != newRate.ask
            || oldRate.bid != newRate.bid
            || oldRate.currency.currencyCode != newRate.currency.currencyCode
    }

    private var hasEnteredAmount: Bool {
        switch activeField {
        case .top: topAmount.minorUnits > 0
        case .bottom: bottomAmount.minorUnits > 0
        }
    }

    private func makeRateDescription(for rate: ExchangeRate) -> String {
        CurrencyConversion.rateDescription(
            base: SupportedCurrencies.usdc,
            quote: rate.currency,
            book: rate,
            convertingFrom: topCurrency,
            to: bottomCurrency
        )
    }

    private func userFacingMessage(for error: Error, fallback: String) -> String {
        guard let apiError = error as? ARQAPIError else { return fallback }
        return apiError.userFacingMessage
    }

    private func recalculateDerivedField() {
        guard currentRate != nil else { return }

        switch activeField {
        case .top:
            applyDerivedConversion(
                sourceAmount: topAmount,
                sourceCurrency: topCurrency,
                targetAmount: bottomAmount,
                targetCurrency: bottomCurrency,
                onConversionFailure: { bottomAmount.reset() }
            )

        case .bottom:
            applyDerivedConversion(
                sourceAmount: bottomAmount,
                sourceCurrency: bottomCurrency,
                targetAmount: topAmount,
                targetCurrency: topCurrency,
                onConversionFailure: { topAmount.reset() }
            )
        }
    }

    private func applyDerivedConversion(
        sourceAmount: MoneyInputViewModel,
        sourceCurrency: AppCurrency,
        targetAmount: MoneyInputViewModel,
        targetCurrency: AppCurrency,
        onConversionFailure: () -> Void
    ) {
        guard let currentRate else { return }

        guard sourceAmount.minorUnits > 0 else {
            targetAmount.reset()
            clearLimitWarningState()
            return
        }

        guard let converted = CurrencyConversion.convert(
            amount: sourceAmount.decimalAmount,
            from: sourceCurrency,
            to: targetCurrency,
            book: currentRate
        ) else {
            onConversionFailure()
            clearLimitWarningState()
            return
        }

        if exceedsDerivedLimit(
            sourceAmount: sourceAmount.decimalAmount,
            from: sourceCurrency,
            to: targetCurrency
        ) || MoneyInputViewModel.minorUnits(for: converted, currency: targetCurrency) == nil {
            noteInputRejectedAtLimit()
            return
        }

        targetAmount.applyConvertedAmount(converted)
        if !isAmountAtLimit {
            showsRejectedAmountWarning = false
        }
    }

    private func exceedsDerivedLimit(
        sourceAmount: Decimal,
        from source: AppCurrency,
        to target: AppCurrency
    ) -> Bool {
        guard target.maxMinorUnits != nil, let currentRate else { return false }

        guard let converted = CurrencyConversion.convert(
            amount: sourceAmount,
            from: source,
            to: target,
            book: currentRate
        ) else {
            return false
        }

        return MoneyInputViewModel.minorUnits(for: converted, currency: target) == nil
    }

    private var usdcSideAmount: MoneyInputViewModel {
        topCurrency.isUSDC ? topAmount : bottomAmount
    }

    private var quoteSideAmount: MoneyInputViewModel {
        topCurrency.isUSDC ? bottomAmount : topAmount
    }

    private func wouldExceedDerivedLimit(
        sourceMinorUnits: Int64,
        from source: AppCurrency,
        to target: AppCurrency
    ) -> Bool {
        guard sourceMinorUnits > 0 else { return false }
        let divisor = Decimal(pow(10.0, Double(source.decimalPlaces)))
        let amount = Decimal(sourceMinorUnits) / divisor
        return exceedsDerivedLimit(sourceAmount: amount, from: source, to: target)
    }

    private var isReceiveCoupledAtLimit: Bool {
        if quoteSideAmount.isAtLimit { return true }
        guard usdcSideAmount.minorUnits > 0 else { return false }
        guard usdcSideAmount.minorUnits < Int64.max else { return false }

        return wouldExceedDerivedLimit(
            sourceMinorUnits: usdcSideAmount.minorUnits + 1,
            from: SupportedCurrencies.usdc,
            to: quoteSideAmount.currency
        )
    }

    private var isSendCoupledAtLimit: Bool {
        if usdcSideAmount.isAtLimit { return true }
        guard quoteSideAmount.minorUnits > 0 else { return false }
        guard quoteSideAmount.minorUnits < Int64.max else { return false }

        return wouldExceedDerivedLimit(
            sourceMinorUnits: quoteSideAmount.minorUnits + 1,
            from: quoteSideAmount.currency,
            to: SupportedCurrencies.usdc
        )
    }

    #if DEBUG
    static func preview(
        topMinorUnits: Int64 = 999_900,
        bottomCurrency: AppCurrency? = nil
    ) -> ExchangeCalculatorViewModel {
        let viewModel = ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        viewModel.seedPreview(
            topMinorUnits: topMinorUnits,
            bottomCurrency: bottomCurrency ?? SupportedCurrencies.defaultQuoteCurrency
        )
        return viewModel
    }

    private func seedPreview(topMinorUnits: Int64, bottomCurrency: AppCurrency) {
        topAmount.setMinorUnits(topMinorUnits)
        self.bottomCurrency = bottomCurrency
        bottomAmount = MoneyInputViewModel(currency: bottomCurrency)
        if let rate = MockExchangeRateRepository.defaultRates[bottomCurrency.code] {
            applyRateUpdate(rate, recalculateAmounts: true)
        }
    }
    #endif
}

extension ExchangeCalculatorViewModel {
    var rateDescription: String {
        guard case .ready(let description, _) = screenState else { return "" }
        return description
    }

    var rateFreshnessLabel: String {
        guard case .ready(_, let freshness) = screenState else { return "" }
        return freshness
    }

    var canPollIndicativeRates: Bool {
        currentRate != nil
    }

    static let maximumAmountReachedMessage = "Maximum amount reached."

    var amountLimitWarning: String? {
        _ = inputValidationTick
        guard showsRejectedAmountWarning || isAmountAtLimit else { return nil }
        return Self.maximumAmountReachedMessage
    }

    private var isAmountAtLimit: Bool {
        topAmount.isAtLimit
            || bottomAmount.isAtLimit
            || isReceiveCoupledAtLimit
            || isSendCoupledAtLimit
    }
}
