import Foundation

struct MockExchangeRateRepository: ExchangeRateRepositoryProtocol, Sendable {
    private let rates: [String: ExchangeRate]
    private let refreshDelay: TimeInterval

    init(rates: [String: ExchangeRate]? = nil, refreshDelay: TimeInterval = 0) {
        self.rates = rates ?? Self.defaultRates
        self.refreshDelay = refreshDelay
    }

    func prefetchRates(for currencies: [AppCurrency], policy: RateRefreshPolicy) async throws {
        _ = currencies
        _ = policy
        if refreshDelay > 0 {
            try await Task.sleep(for: .seconds(refreshDelay))
        }
    }

    func exchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate {
        if refreshDelay > 0, policy == .forceRefresh {
            try await Task.sleep(for: .seconds(refreshDelay))
        }
        guard let rate = rates[currency.currencyCode] else {
            throw ExchangeRateRepositoryError.missingRate(currency)
        }
        return rate
    }

    func refreshExchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate {
        try await prefetchRates(for: [currency], policy: policy)
        return try await exchangeRate(for: currency, policy: .useCacheIfFresh)
    }

    static let defaultRates: [String: ExchangeRate] = {
        let mxn = SupportedCurrencies.pickerCurrencies.first { $0.code == "MXN" }!
        let ars = SupportedCurrencies.pickerCurrencies.first { $0.code == "ARS" }!
        let cop = SupportedCurrencies.pickerCurrencies.first { $0.code == "COP" }!
        let brl = SupportedCurrencies.pickerCurrencies.first { $0.code == "BRL" }!
        return [
            mxn.code: ExchangeRate(currency: mxn, ask: 18.4105, bid: 18.40697, updatedAt: Date()),
            ars.code: ExchangeRate(currency: ars, ask: 1551, bid: 1539.42903, updatedAt: Date()),
            cop.code: ExchangeRate(currency: cop, ask: 3832.42, bid: 3830, updatedAt: Date()),
            brl.code: ExchangeRate(currency: brl, ask: 5.12, bid: 5.10, updatedAt: Date())
        ]
    }()
}
