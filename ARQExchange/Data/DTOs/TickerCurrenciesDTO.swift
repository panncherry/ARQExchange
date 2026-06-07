import Foundation

/// Models for `GET /v1/tickers-currencies` (not yet available).
///
/// Expected response:
/// ```json
/// ["MXN", "ARS", "BRL", "COP"]
/// ```
///
/// Picker currencies use `SupportedCurrencies` until this endpoint ships.
struct TickerCurrenciesResponse: Sendable, Equatable {
    let codes: [String]

    init(codes: [String]) {
        self.codes = codes
    }
}

extension TickerCurrenciesResponse: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        codes = try [String](from: decoder)
    }
}
