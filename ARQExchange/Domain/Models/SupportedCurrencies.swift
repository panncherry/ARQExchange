import Foundation

enum SupportedCurrencies: Sendable {
    nonisolated static let usdcCode = "USDc"

    nonisolated static let usdc = AppCurrency(
        code: usdcCode,
        countryCode: "US",
        isSupported: true,
        sortPriority: -1,
        maxMinorUnits: 999_999_999_999
    )

    /// Quote currencies with live USDC rates on `GET /v1/tickers`.
    /// Add more here when the API supports them (or when `tickers-currencies` ships).
    nonisolated static let all: [AppCurrency] = [
        .init(code: "ARS", countryCode: "AR", isSupported: true, sortPriority: 0, maxMinorUnits: 100_000_000_00),
        .init(code: "BRL", countryCode: "BR", isSupported: true, sortPriority: 1, maxMinorUnits: 100_000_000_00),
        .init(code: "COP", countryCode: "CO", isSupported: true, sortPriority: 2, maxMinorUnits: 100_000_000_00),
        .init(code: "MXN", countryCode: "MX", isSupported: true, sortPriority: 3, maxMinorUnits: 100_000_000_00)
    ]

    nonisolated static var supported: [AppCurrency] {
        all
            .filter(\.isSupported)
            .sorted { $0.sortPriority < $1.sortPriority }
    }

    /// Currencies shown in the picker (local config until `GET /v1/tickers-currencies` is available).
    nonisolated static var pickerCurrencies: [AppCurrency] {
        supported.filter(\.isSelectableInPicker)
    }

    nonisolated static var defaultQuoteCurrency: AppCurrency {
        pickerCurrencies.first(where: { $0.code == "MXN" }) ?? pickerCurrencies[0]
    }

    /// Comma-separated ISO codes for all picker currencies (tests and future tickers-currencies integration).
    nonisolated static var apiTickerCodes: String {
        pickerCurrencies.map(\.isoCode).joined(separator: ",")
    }

    nonisolated static func fromTickerBook(_ book: String) -> AppCurrency? {
        let parts = book.lowercased().split(separator: "_")
        guard parts.count == 2, parts[0] == "usdc" else { return nil }
        let suffix = String(parts[1]).uppercased()
        return pickerCurrencies.first { $0.isoCode.uppercased() == suffix }
    }
}
