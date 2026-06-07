import Foundation
import Testing
@testable import ARQExchange

@MainActor
struct MoneyInputViewModelTests {
    @Test func insertsDigitsIntoMinorUnits() {
        let model = MoneyInputViewModel(currency: SupportedCurrencies.usdc)

        model.insertDigit(1)
        model.insertDigit(2)
        model.insertDigit(3)
        model.insertDigit(4)

        #expect(model.minorUnits == 1234)
        #expect(model.decimalAmount == Decimal(string: "12.34"))
    }

    @Test func respectsCurrencyMaxMinorUnits() {
        let currency = AppCurrency(
            code: "TST",
            countryCode: "US",
            isSupported: true,
            sortPriority: 0,
            maxMinorUnits: 999
        )
        let model = MoneyInputViewModel(currency: currency)

        for digit in [9, 9, 9, 9] {
            model.insertDigit(digit)
        }

        #expect(model.minorUnits == 999)
    }

    @Test func applyKeyboardDigitsRejectsInputBeyondMaxWithoutChangingAmount() {
        let model = MoneyInputViewModel(currency: SupportedCurrencies.usdc)

        model.applyKeyboardDigits("100000000000")
        model.applyKeyboardDigits("100000000000000")

        #expect(model.minorUnits == 100_000_000_000)
        #expect(model.isAtLimit == false)
    }

    @Test func applyKeyboardDigitsAcceptsExactMaxAndFlagsLimit() {
        let model = MoneyInputViewModel(currency: SupportedCurrencies.usdc)

        model.applyKeyboardDigits("999999999999")

        #expect(model.minorUnits == 999_999_999_999)
        #expect(model.isAtLimit == true)
    }

    @Test func applyKeyboardDigitsRejectsFurtherDigitsAtMax() {
        let model = MoneyInputViewModel(currency: SupportedCurrencies.usdc)

        model.applyKeyboardDigits("999999999999")
        let before = model.minorUnits
        model.applyKeyboardDigits("9999999999999")

        #expect(model.minorUnits == before)
        #expect(model.isAtLimit == true)
    }

    @Test func applyConvertedAmountSetsExactConvertedValue() {
        let model = MoneyInputViewModel(currency: SupportedCurrencies.usdc)

        model.applyConvertedAmount(Decimal(string: "12.34")!)

        #expect(model.minorUnits == 1234)
    }

    @Test func minorUnitsHelperReturnsNilWhenAboveCurrencyMax() {
        let currency = AppCurrency(
            code: "TST",
            countryCode: "US",
            isSupported: true,
            sortPriority: 0,
            maxMinorUnits: 500
        )

        #expect(MoneyInputViewModel.minorUnits(for: Decimal(string: "9.99")!, currency: currency) == nil)
        #expect(MoneyInputViewModel.minorUnits(for: Decimal(string: "5.00")!, currency: currency) == 500)
    }
}

@MainActor
struct AmountLimitWarningTests {
    @Test func showsWarningWhenEitherFieldReachesLimit() async {
        let viewModel = ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        await viewModel.activateScreen()

        viewModel.selectField(.bottom)
        viewModel.updateBottomKeyboardInput(String(SupportedCurrencies.defaultQuoteCurrency.maxMinorUnits!))

        #expect(viewModel.amountLimitWarning == ExchangeCalculatorViewModel.maximumAmountReachedMessage)
    }

    @Test func showsWarningWhenRejectedInputWouldExceedLimit() async {
        let viewModel = ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        await viewModel.activateScreen()

        viewModel.selectField(.bottom)
        viewModel.updateBottomKeyboardInput("999")
        viewModel.updateBottomKeyboardInput(String(SupportedCurrencies.defaultQuoteCurrency.maxMinorUnits! + 1))

        #expect(viewModel.bottomKeyboardDigits == "999")
        #expect(viewModel.amountLimitWarning == ExchangeCalculatorViewModel.maximumAmountReachedMessage)
    }

    @Test func topInputStopsWhenConvertedBottomWouldExceedLimit() async {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let rates: [String: ExchangeRate] = [
            mxn.code: ExchangeRate(currency: mxn, ask: 20, bid: 20, updatedAt: Date())
        ]
        let viewModel = ExchangeCalculatorViewModel(
            repository: MockExchangeRateRepository(rates: rates)
        )
        await viewModel.activateScreen()

        viewModel.selectField(.top)
        viewModel.updateTopKeyboardInput("500000000")

        #expect(viewModel.bottomFormattedAmount.contains("100,000,000"))
        let topBeforeOverflow = viewModel.topKeyboardDigits

        viewModel.updateTopKeyboardInput("5000000000")

        #expect(viewModel.topKeyboardDigits == topBeforeOverflow)
        #expect(viewModel.amountLimitWarning == ExchangeCalculatorViewModel.maximumAmountReachedMessage)
    }
}

@MainActor
struct ExchangeCalculatorReliabilityTests {
    @Test func rateIncreaseNearLimitKeepsDerivedAmountAndShowsLimitWarning() async {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let initialRate = ExchangeRate(currency: mxn, ask: 20, bid: 20, updatedAt: Date())
        let higherRate = ExchangeRate(currency: mxn, ask: 25, bid: 25, updatedAt: Date())
        let repository = SteppingExchangeRateRepository(rates: [initialRate, higherRate])
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        await viewModel.activateScreen()
        viewModel.selectField(.top)
        viewModel.updateTopKeyboardInput("500000000")

        #expect(viewModel.bottomFormattedAmount.contains("100,000,000"))
        let bottomBeforeRefresh = viewModel.bottomFormattedAmount

        await viewModel.pullToRefresh()

        #expect(viewModel.bottomFormattedAmount == bottomBeforeRefresh)
        #expect(viewModel.amountLimitWarning == ExchangeCalculatorViewModel.maximumAmountReachedMessage)
    }

    @Test func clearsLimitWarningAfterSwap() async {
        let viewModel = ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        await viewModel.activateScreen()

        viewModel.selectField(.bottom)
        viewModel.updateBottomKeyboardInput("999")
        viewModel.updateBottomKeyboardInput(String(SupportedCurrencies.defaultQuoteCurrency.maxMinorUnits! + 1))

        #expect(viewModel.amountLimitWarning == ExchangeCalculatorViewModel.maximumAmountReachedMessage)

        await viewModel.swapCurrencies()

        #expect(viewModel.amountLimitWarning == nil)
    }

    @Test func refreshFailureWithCachedRateSurfacesMessage() async {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let repository = FailOnSubsequentRefreshRepository(rate: rate)
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        await viewModel.activateScreen()
        #expect(viewModel.refreshFailureMessage == nil)

        await viewModel.pullToRefresh()

        #expect(viewModel.refreshFailureMessage != nil)
        #expect(viewModel.rateDescription.contains("MXN"))
    }

    @Test func concurrentSwapRequestsOnlySwapOnce() async {
        let viewModel = ExchangeCalculatorViewModel(
            repository: MockExchangeRateRepository(refreshDelay: 0.05)
        )
        await viewModel.activateScreen()

        #expect(viewModel.topCurrency.isUSDC)

        async let firstSwap: Void = viewModel.swapCurrencies()
        async let secondSwap: Void = viewModel.swapCurrencies()
        _ = await (firstSwap, secondSwap)

        #expect(viewModel.topCurrency.code == "MXN")
    }

    @Test func runIndicativeRefreshLoopRespectsCancellation() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(ratesByCode: ratesByCurrencyCode([rate]))
        let repository = ExchangeRateRepository(api: api, maxCacheAge: 0)
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        await viewModel.activateScreen()
        let callsAfterActivate = await api.fetchTickersCallCount

        let loop = Task { await viewModel.runIndicativeRefreshLoop() }
        try await Task.sleep(for: .milliseconds(10))
        loop.cancel()
        _ = await loop.value

        await viewModel.refreshOnReturnToForeground()

        #expect(await api.fetchTickersCallCount > callsAfterActivate)
    }
}

struct CurrencyConversionTests {
    @Test func convertsUSDCToQuoteUsingAsk() {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.isoCode == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.4105, bid: 18.40697, updatedAt: Date())

        let result = CurrencyConversion.convert(
            amount: 1,
            from: SupportedCurrencies.usdc,
            to: mxn,
            book: rate
        )

        #expect(result == 18.4105)
    }

    @Test func convertsQuoteToUSDCUsingBid() {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.isoCode == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.4105, bid: 18.40697, updatedAt: Date())

        let result = CurrencyConversion.convert(
            amount: 18.40697,
            from: mxn,
            to: SupportedCurrencies.usdc,
            book: rate
        )

        #expect(result == 1)
    }

    @Test func rateDescriptionUsesAskForUSDCToQuote() {
        let ars = SupportedCurrencies.pickerCurrencies.first { $0.isoCode == "ARS" }!
        let rate = ExchangeRate(currency: ars, ask: 1503.89, bid: 1498.753725, updatedAt: Date())

        let description = CurrencyConversion.rateDescription(
            base: SupportedCurrencies.usdc,
            quote: ars,
            book: rate,
            convertingFrom: SupportedCurrencies.usdc,
            to: ars
        )

        #expect(description == "1 USDc = 1,503.89 ARS")
    }

    @Test func rateDescriptionUsesBidForQuoteToUSDC() {
        let ars = SupportedCurrencies.pickerCurrencies.first { $0.isoCode == "ARS" }!
        let rate = ExchangeRate(currency: ars, ask: 1503.89, bid: 1498.753725, updatedAt: Date())

        let description = CurrencyConversion.rateDescription(
            base: SupportedCurrencies.usdc,
            quote: ars,
            book: rate,
            convertingFrom: ars,
            to: SupportedCurrencies.usdc
        )

        #expect(description == "1 USDc = 1,498.7537 ARS")
    }
}

struct SupportedCurrenciesTests {
    @Test func pickerExcludesUSDC() {
        #expect(SupportedCurrencies.pickerCurrencies.contains { $0.isUSDC } == false)
        #expect(SupportedCurrencies.pickerCurrencies.count == SupportedCurrencies.supported.count)
    }
}

@MainActor
struct ExchangeCalculatorViewModelTests {
    @Test func enteringAmountUpdatesConvertedValue() async {
        let viewModel = ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        await viewModel.activateScreen()

        viewModel.selectField(.top)
        viewModel.updateTopKeyboardInput("99999")

        #expect(viewModel.topFormattedAmount.contains("999.99"))
        #expect(viewModel.bottomFormattedAmount != viewModel.topFormattedAmount)
    }

    @Test func selectingCurrencyLoadsRateWithoutError() async {
        let viewModel = ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        await viewModel.activateScreen()
        await viewModel.selectCurrency(
            SupportedCurrencies.pickerCurrencies.first { $0.code == "ARS" }!
        )
        #expect(viewModel.rateDescription.contains("ARS"))
    }

    @Test func pullToRefreshMakesSingleAPICall() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let mxnRate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(ratesByCode: ratesByCurrencyCode([mxnRate]))
        let repository = ExchangeRateRepository(api: api)
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        await viewModel.activateScreen()
        let callsBeforePull = await api.fetchTickersCallCount

        await viewModel.pullToRefresh()

        #expect(await api.fetchTickersCallCount == callsBeforePull + 1)
    }

    @Test func refreshUpdatesConvertedAmountWhenRateChanges() async {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let initialRate = ExchangeRate(currency: mxn, ask: 18, bid: 18, updatedAt: Date())
        let updatedRate = ExchangeRate(currency: mxn, ask: 20, bid: 20, updatedAt: Date())
        let repository = SteppingExchangeRateRepository(rates: [initialRate, updatedRate])
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        await viewModel.activateScreen()
        viewModel.selectField(.top)
        viewModel.updateTopKeyboardInput("10000")

        let convertedBefore = viewModel.bottomFormattedAmount
        await viewModel.pullToRefresh()

        #expect(viewModel.topFormattedAmount.contains("100"))
        #expect(viewModel.bottomFormattedAmount != convertedBefore)
        #expect(viewModel.bottomFormattedAmount.contains("2,000") || viewModel.bottomFormattedAmount.contains("2000"))
        #expect(viewModel.rateDescription.contains("20"))
    }

    @Test func coalescedLaunchRefreshStillShowsRateHeader() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let mxnRate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(
            ratesByCode: ratesByCurrencyCode([mxnRate]),
            fullRefreshDelayMilliseconds: 50
        )
        let repository = ExchangeRateRepository(api: api)
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        async let initialLoad: Void = viewModel.retryLoading()
        async let overlappingRefresh: Void = viewModel.refreshOnReturnToForeground()
        _ = await (initialLoad, overlappingRefresh)

        #expect(viewModel.rateDescription.contains("MXN"))
        #expect(viewModel.rateFreshnessLabel.isEmpty == false)
    }

    @Test func coalescedOverlappingRefreshesShareOneFetch() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let mxnRate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(
            ratesByCode: ratesByCurrencyCode([mxnRate]),
            fullRefreshDelayMilliseconds: 100
        )
        let repository = ExchangeRateRepository(api: api)
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        async let first: Void = viewModel.refreshOnReturnToForeground()
        async let second: Void = viewModel.refreshOnReturnToForeground()
        _ = await (first, second)

        #expect(await api.fetchTickersCallCount == 1)
    }

    @Test func activateAndPickerSelectionFetchOnlyActiveQuoteCurrency() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let cop = SupportedCurrencies.pickerCurrencies.first { $0.code == "COP" }!
        let mxnRate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let copRate = ExchangeRate(currency: cop, ask: 3832.42, bid: 3830, updatedAt: Date())
        let api = TrackingExchangeRateAPI(ratesByCode: ratesByCurrencyCode([mxnRate, copRate]))
        let repository = ExchangeRateRepository(api: api)
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        await viewModel.activateScreen()
        #expect(await api.lastFetchedCurrencyCodes == ["MXN"])

        await viewModel.selectCurrency(cop)
        #expect(await api.lastFetchedCurrencyCodes == ["COP"])
    }

    @Test func swapPreservesAmountsAndSwapsCurrencies() async {
        let viewModel = ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        await viewModel.activateScreen()

        viewModel.selectField(.top)
        viewModel.updateTopKeyboardInput("10000")
        await viewModel.swapCurrencies()

        #expect(viewModel.topCurrency.code == "MXN")
        #expect(viewModel.bottomCurrency.code == "USDc")
        #expect(viewModel.activeField == .top)
    }

    @Test func swapUpdatesRateForNewTopToBottomDirection() async {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let ars = SupportedCurrencies.pickerCurrencies.first { $0.code == "ARS" }!
        let rates: [String: ExchangeRate] = [
            mxn.code: ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date()),
            ars.code: ExchangeRate(currency: ars, ask: 1505.29, bid: 1500.33, updatedAt: Date())
        ]
        let viewModel = ExchangeCalculatorViewModel(
            repository: MockExchangeRateRepository(rates: rates)
        )
        await viewModel.activateScreen()
        await viewModel.selectCurrency(ars)

        viewModel.selectField(.top)
        #expect(viewModel.rateDescription == "1 USDc = 1,505.29 ARS")

        await viewModel.swapCurrencies()

        #expect(viewModel.topCurrency.code == "ARS")
        #expect(viewModel.bottomCurrency.code == "USDc")
        #expect(viewModel.activeField == .top)
        #expect(viewModel.rateDescription == "1 USDc = 1,500.33 ARS")
    }

    @Test func swapDuringCurrencySelectionDoesNotApplyToWrongRow() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let cop = SupportedCurrencies.pickerCurrencies.first { $0.code == "COP" }!
        let mxnRate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let copRate = ExchangeRate(currency: cop, ask: 3832.42, bid: 3830, updatedAt: Date())
        let api = TrackingExchangeRateAPI(
            ratesByCode: ratesByCurrencyCode([mxnRate, copRate]),
            fullRefreshDelayMilliseconds: 100
        )
        let repository = ExchangeRateRepository(api: api)
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        await viewModel.activateScreen()

        let selectionTask = Task { @MainActor in
            await viewModel.selectCurrency(cop)
        }
        try await Task.sleep(for: .milliseconds(20))
        await viewModel.swapCurrencies()
        await selectionTask.value

        #expect(viewModel.topCurrency.code == "MXN")
        #expect(viewModel.bottomCurrency.code == "USDc")
        #expect(viewModel.topCurrency.code != "COP")
        #expect(viewModel.bottomCurrency.code != "COP")
    }

    @Test func swapDuringCurrencySelectionFetchesPostSwapQuote() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let cop = SupportedCurrencies.pickerCurrencies.first { $0.code == "COP" }!
        let mxnRate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let copRate = ExchangeRate(currency: cop, ask: 3832.42, bid: 3830, updatedAt: Date())
        let api = TrackingExchangeRateAPI(
            ratesByCode: ratesByCurrencyCode([mxnRate, copRate]),
            fullRefreshDelayMilliseconds: 100
        )
        let repository = ExchangeRateRepository(api: api)
        let viewModel = ExchangeCalculatorViewModel(repository: repository)

        await viewModel.activateScreen()

        let selectionTask = Task { @MainActor in
            await viewModel.selectCurrency(cop)
        }
        try await Task.sleep(for: .milliseconds(20))
        await viewModel.swapCurrencies()
        await selectionTask.value

        #expect(await api.lastFetchedCurrencyCodes == ["MXN"])
        #expect(viewModel.rateDescription.contains("MXN"))
    }

    @Test func selectCurrencyDoesNotChangeQuoteWhenRateFetchFails() async {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let cop = SupportedCurrencies.pickerCurrencies.first { $0.code == "COP" }!
        let rates: [String: ExchangeRate] = [
            mxn.code: ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        ]
        let viewModel = ExchangeCalculatorViewModel(
            repository: MockExchangeRateRepository(rates: rates)
        )
        await viewModel.activateScreen()

        #expect(viewModel.bottomCurrency.code == "MXN")
        let rateBeforeFailure = viewModel.rateDescription

        await viewModel.selectCurrency(cop)

        #expect(viewModel.bottomCurrency.code == "MXN")
        #expect(viewModel.rateDescription == rateBeforeFailure)
    }
}

@MainActor
struct ExchangeRateRepositoryTests {
    @Test func returnsCachedRateWithoutRefetchingWhileFresh() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(ratesByCode: ratesByCurrencyCode([rate]))
        let repository = ExchangeRateRepository(api: api, maxCacheAge: 30)

        try await repository.prefetchRates(for: [mxn], policy: .forceRefresh)
        _ = try await repository.exchangeRate(for: mxn, policy: .useCacheIfFresh)

        #expect(await api.fetchTickersCallCount == 1)
        #expect(await api.lastFetchedCurrencyCodes == ["MXN"])

        _ = try await repository.exchangeRate(for: mxn, policy: .useCacheIfFresh)
        #expect(await api.fetchTickersCallCount == 1)
    }

    @Test func forceRefreshAlwaysFetchesAgain() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(ratesByCode: ratesByCurrencyCode([rate]))
        let repository = ExchangeRateRepository(api: api, maxCacheAge: 30)

        try await repository.prefetchRates(for: [mxn], policy: .forceRefresh)
        try await repository.prefetchRates(for: [mxn], policy: .forceRefresh)

        #expect(await api.fetchTickersCallCount == 2)
    }

    @Test func freshReadAfterForcedPrefetchDoesNotRefetch() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(ratesByCode: ratesByCurrencyCode([rate]))
        let repository = ExchangeRateRepository(api: api, maxCacheAge: 30)

        try await repository.prefetchRates(for: [mxn], policy: .forceRefresh)
        _ = try await repository.exchangeRate(for: mxn, policy: .useCacheIfFresh)

        #expect(await api.fetchTickersCallCount == 1)
    }

    @Test func concurrentFullRefreshesShareInFlightRequest() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(
            ratesByCode: ratesByCurrencyCode([rate]),
            fullRefreshDelayMilliseconds: 100
        )
        let repository = ExchangeRateRepository(api: api, maxCacheAge: 30)

        async let prefetch: Void = repository.prefetchRates(for: [mxn], policy: .forceRefresh)
        async let exchangeRate = repository.exchangeRate(for: mxn, policy: .forceRefresh)
        _ = try await (prefetch, exchangeRate)

        #expect(await api.fetchTickersCallCount == 1)
    }

    @Test func cancellingOneRefreshWaiterDoesNotCancelSharedRequest() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let rate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let api = TrackingExchangeRateAPI(
            ratesByCode: ratesByCurrencyCode([rate]),
            fullRefreshDelayMilliseconds: 100
        )
        let repository = ExchangeRateRepository(api: api, maxCacheAge: 30)

        let leader = Task {
            try await repository.prefetchRates(for: [mxn], policy: .forceRefresh)
        }
        try await Task.sleep(for: .milliseconds(20))
        let cancelledWaiter = Task {
            try await repository.exchangeRate(for: mxn, policy: .forceRefresh)
        }

        cancelledWaiter.cancel()
        try await leader.value
        _ = try await repository.exchangeRate(for: mxn, policy: .useCacheIfFresh)

        #expect(await api.fetchTickersCallCount == 1)
    }

    @Test func singleCurrencyFallbackUsesIndividualFreshness() async throws {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let cop = SupportedCurrencies.pickerCurrencies.first { $0.code == "COP" }!
        let mxnRate = ExchangeRate(currency: mxn, ask: 18.41, bid: 18.40, updatedAt: Date())
        let copRate = ExchangeRate(currency: cop, ask: 3832.42, bid: 3830, updatedAt: Date())
        let api = TrackingExchangeRateAPI(
            ratesByCode: ratesByCurrencyCode([mxnRate], tickerRates: [copRate])
        )
        let repository = ExchangeRateRepository(api: api, maxCacheAge: 30)

        try await repository.prefetchRates(for: [mxn], policy: .forceRefresh)
        _ = try await repository.exchangeRate(for: cop, policy: .useCacheIfFresh)
        _ = try await repository.exchangeRate(for: cop, policy: .useCacheIfFresh)

        #expect(await api.fetchTickersCallCount == 2)
        #expect(await api.lastFetchedCurrencyCodes == ["COP"])
    }
}

@MainActor
struct RateHeaderViewModelTests {
    @Test func refreshSetsLiveRateLabel() async {
        let viewModel = ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        await viewModel.activateScreen()
        #expect(viewModel.rateFreshnessLabel == "Live rate")
    }
}

struct RateFreshnessFormatterTests {
    @Test func freshRateShowsLiveRate() {
        let now = Date()
        #expect(RateFreshnessFormatter.indicativeLabel(updatedAt: now, now: now) == "Live rate")
    }

    @Test func staleRateShowsUpdatedTime() {
        let now = Date()
        let stale = now.addingTimeInterval(-120)
        let label = RateFreshnessFormatter.indicativeLabel(updatedAt: stale, now: now)
        #expect(label.hasPrefix("Updated "))
        #expect(label.contains("Live rate") == false)
    }
}

private final class FailOnSubsequentRefreshRepository: ExchangeRateRepositoryProtocol, @unchecked Sendable {
    private let rate: ExchangeRate
    private var refreshAttempts = 0

    init(rate: ExchangeRate) {
        self.rate = rate
    }

    func prefetchRates(for currencies: [AppCurrency], policy: RateRefreshPolicy) async throws {
        _ = currencies
        _ = policy
        refreshAttempts += 1
        if refreshAttempts > 1 {
            throw URLError(.notConnectedToInternet)
        }
    }

    func exchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate {
        _ = currency
        _ = policy
        return rate
    }

    func refreshExchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate {
        try await prefetchRates(for: [currency], policy: policy)
        return try await exchangeRate(for: currency, policy: .useCacheIfFresh)
    }
}

private final class SteppingExchangeRateRepository: ExchangeRateRepositoryProtocol, @unchecked Sendable {
    private let rates: [ExchangeRate]
    private var fetchCount = 0

    init(rates: [ExchangeRate]) {
        self.rates = rates
    }

    func prefetchRates(for currencies: [AppCurrency], policy: RateRefreshPolicy) async throws {
        _ = currencies
        _ = policy
    }

    func exchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate {
        _ = currency
        _ = policy
        fetchCount += 1
        return rates[min(fetchCount - 1, rates.count - 1)]
    }

    func refreshExchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate {
        _ = policy
        fetchCount += 1
        return rates[min(fetchCount - 1, rates.count - 1)]
    }
}

@MainActor
private func ratesByCurrencyCode(
    _ rates: [ExchangeRate],
    tickerRates: [ExchangeRate] = []
) -> [String: ExchangeRate] {
    var merged = Dictionary(uniqueKeysWithValues: rates.map { ($0.currency.currencyCode, $0) })
    for rate in tickerRates {
        merged[rate.currency.currencyCode] = rate
    }
    return merged
}

private actor TrackingExchangeRateAPI: ExchangeRateAPI {
    private let ratesByCode: [String: ExchangeRate]
    private let refreshDelayMilliseconds: Int
    private var fetchTickersCalls = 0
    private var lastFetchedCodes: [String] = []

    var fetchTickersCallCount: Int {
        fetchTickersCalls
    }

    var lastFetchedCurrencyCodes: [String] {
        lastFetchedCodes
    }

    init(
        ratesByCode: [String: ExchangeRate],
        fullRefreshDelayMilliseconds: Int = 0
    ) {
        self.ratesByCode = ratesByCode
        self.refreshDelayMilliseconds = fullRefreshDelayMilliseconds
    }

    func fetchTickers(for currencies: [AppCurrency]) async throws -> [ExchangeRate] {
        fetchTickersCalls += 1
        lastFetchedCodes = currencies.map(\.currencyCode)

        if refreshDelayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(refreshDelayMilliseconds))
        }

        return currencies.compactMap { ratesByCode[$0.currencyCode] }
    }
}
