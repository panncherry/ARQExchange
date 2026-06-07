import Foundation

/// Raw ticker payload returned by `GET /v1/tickers`.
///
/// Numeric values arrive as strings to preserve the API precision until conversion
/// into Decimal-backed domain values.
struct TickerDTO: Sendable {
    let ask: String
    let bid: String
    let book: String
    let date: String
}

extension TickerDTO: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ask = try container.decode(String.self, forKey: .ask)
        bid = try container.decode(String.self, forKey: .bid)
        book = try container.decode(String.self, forKey: .book)
        date = try container.decode(String.self, forKey: .date)
    }

    private enum CodingKeys: String, CodingKey {
        case ask
        case bid
        case book
        case date
    }
}

extension TickerDTO {
    /// Validates the ticker book, parses decimal prices, and converts the DTO into the domain model.
    nonisolated func toDomain() throws -> ExchangeRate {
        guard let currency = SupportedCurrencies.fromTickerBook(book) else {
            throw ARQAPIError.invalidResponse(message: "Unsupported ticker book '\(book)'.")
        }

        guard let askDecimal = Decimal(string: ask, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ARQAPIError.invalidResponse(message: "Ticker book '\(book)' has an invalid ask value: '\(ask)'.")
        }

        guard let bidDecimal = Decimal(string: bid, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ARQAPIError.invalidResponse(message: "Ticker book '\(book)' has an invalid bid value: '\(bid)'.")
        }

        let updatedAt = try TickerDateParser.parse(date)

        return ExchangeRate(
            currency: currency,
            ask: askDecimal,
            bid: bidDecimal,
            updatedAt: updatedAt
        )
    }
}

/// Parses DolarApp ticker timestamps across documented and observed API formats.
enum TickerDateParser {
    nonisolated static func parse(_ value: String) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ARQAPIError.invalidResponse(message: "Ticker date is empty.")
        }

        if let date = iso8601WithTimezone.date(from: trimmed) {
            return date
        }

        if let date = fractionalUTC.date(from: trimmed) {
            return date
        }

        if let date = fractionalUTCShort.date(from: trimmed) {
            return date
        }

        if let date = iso8601WithoutFractional.date(from: trimmed) {
            return date
        }

        throw ARQAPIError.invalidResponse(message: "Ticker date '\(value)' is not a supported timestamp format.")
    }

    nonisolated(unsafe) private static let iso8601WithTimezone: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601WithoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// API timestamps like `2026-06-04T20:09:43.692257636` (UTC, no suffix, up to 9 fractional digits).
    nonisolated private static let fractionalUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS"
        return formatter
    }()

    nonisolated private static let fractionalUTCShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter
    }()
}
