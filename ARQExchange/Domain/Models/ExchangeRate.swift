import Foundation

/// Domain representation of a USDC quote book for one supported quote currency.
struct ExchangeRate: Sendable {
    /// Quote currency represented by the API book suffix, e.g. `MXN` for `usdc_mxn`.
    let currency: AppCurrency
    /// Price used when converting from USDc into the quote currency.
    let ask: Decimal
    /// Price used when converting from the quote currency back into USDc.
    let bid: Decimal
    /// Timestamp supplied by the ticker API for freshness display.
    let updatedAt: Date
}

extension ExchangeRate: Equatable {
    nonisolated static func == (lhs: ExchangeRate, rhs: ExchangeRate) -> Bool {
        lhs.currency == rhs.currency
            && lhs.ask == rhs.ask
            && lhs.bid == rhs.bid
            && lhs.updatedAt == rhs.updatedAt
    }
}
