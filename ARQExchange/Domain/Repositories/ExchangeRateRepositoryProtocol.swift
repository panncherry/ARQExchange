import Foundation

/// Repository boundary for rate lookup, caching, and refresh policy decisions.
protocol ExchangeRateRepositoryProtocol: Sendable {
    /// Warms the cache for one or more quote currencies without returning a specific rate.
    func prefetchRates(for currencies: [AppCurrency], policy: RateRefreshPolicy) async throws

    /// Returns a rate using the supplied cache policy.
    func exchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate

    /// Forces the repository path used by UI refresh actions to fetch/read one active quote rate.
    func refreshExchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate
}

/// Repository-level failure when requested quote data is unavailable after refresh.
enum ExchangeRateRepositoryError: Error, Sendable {
    case missingRate(AppCurrency)
}

extension ExchangeRateRepositoryError: Equatable {
    nonisolated static func == (lhs: ExchangeRateRepositoryError, rhs: ExchangeRateRepositoryError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingRate(left), .missingRate(right)):
            left.currencyCode == right.currencyCode
        }
    }
}
