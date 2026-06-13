import Foundation

/// Models for `GET /v1/tickers-currencies` (not yet available).
///
/// Expected response:
/// ```json
/// ["MXN", "ARS", "BRL", "COP"]
/// ```
///
/// Picker currencies use `SupportedCurrencies` until this endpoint ships.
struct TickerCurrenciesResponse: Equatable {
    let codes: [TickerCode]
}

extension TickerCurrenciesResponse: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        codes = try [TickerCode](from: decoder)
    }
}
