import Foundation

/// Currency metadata used by formatting, picker presentation, and amount limits.
struct AppCurrency: Identifiable, Codable, Sendable {
    /// App-facing display code. USDc intentionally differs from ISO `USD`.
    let code: String
    /// ISO country code used to derive a flag glyph for compact currency rows.
    let countryCode: String
    /// Whether the currency is currently available in the local fallback catalog.
    let isSupported: Bool
    /// Stable ordering used by the picker while the remote catalog endpoint is unavailable.
    let sortPriority: Int
    /// Optional maximum in minor units to prevent unrealistic or overflowing input.
    let maxMinorUnits: Int64?

    nonisolated init(
        code: String,
        countryCode: String,
        isSupported: Bool,
        sortPriority: Int,
        maxMinorUnits: Int64?
    ) {
        self.code = code
        self.countryCode = countryCode
        self.isSupported = isSupported
        self.sortPriority = sortPriority
        self.maxMinorUnits = maxMinorUnits
    }

    var id: String { code }

    /// Stable currency identifier safe to read from any actor context.
    nonisolated var currencyCode: String { code }

    /// ISO code used for formatting and API requests.
    nonisolated var isoCode: String {
        switch code {
        case SupportedCurrencies.usdcCode: "USD"
        default: code
        }
    }

    /// Flag glyph derived from `countryCode`; falls back for invalid codes.
    nonisolated var flagEmoji: String {
        FlagEmoji.from(countryCode: countryCode)
    }

    /// Number of decimal places used for minor-unit storage and currency formatting.
    nonisolated var decimalPlaces: Int {
        switch isoCode {
        case "JPY", "KRW": 0
        default: 2
        }
    }

    nonisolated var isUSDC: Bool {
        code == SupportedCurrencies.usdcCode
    }

    nonisolated var isSelectableInPicker: Bool {
        !isUSDC
    }

    /// Formats a stored minor-unit amount using the currency's ISO formatting code.
    @MainActor
    func formattedAmount(minorUnits: Int64) -> String {
        let divisor = Decimal(pow(10.0, Double(decimalPlaces)))
        let amount = Decimal(minorUnits) / divisor

        return amount.formatted(
            .currency(code: isoCode)
                .locale(Locale(identifier: "en_US"))
                .precision(.fractionLength(decimalPlaces))
        )
    }

}

extension AppCurrency: Hashable {
    nonisolated static func == (lhs: AppCurrency, rhs: AppCurrency) -> Bool {
        lhs.code == rhs.code
            && lhs.countryCode == rhs.countryCode
            && lhs.isSupported == rhs.isSupported
            && lhs.sortPriority == rhs.sortPriority
            && lhs.maxMinorUnits == rhs.maxMinorUnits
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        hasher.combine(countryCode)
        hasher.combine(isSupported)
        hasher.combine(sortPriority)
        hasher.combine(maxMinorUnits)
    }
}

enum FlagEmoji {
    nonisolated static func from(countryCode: String) -> String {
        let scalars = countryCode.uppercased().unicodeScalars.filter { $0.value >= 65 && $0.value <= 90 }
        guard scalars.count == 2 else { return "🏳️" }
        return scalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init)
            .joined()
    }
}
