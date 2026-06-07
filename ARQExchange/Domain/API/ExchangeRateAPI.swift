import Foundation

protocol ExchangeRateAPI: Sendable {
    /// Fetches USDC quote rates for the given quote currencies via `GET /v1/tickers?currencies=...`.
    func fetchTickers(for currencies: [AppCurrency]) async throws -> [ExchangeRate]
}
