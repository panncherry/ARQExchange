import Foundation

/// Pure exchange math: USDC ↔ quote using book **ask** / **bid** (no networking or UI).
enum CurrencyConversion {
    /// Rate from API book `usdc_<quote>`: **ask** when buying quote with USDC, **bid** when selling quote for USDC.
    static func rate(from source: AppCurrency, to target: AppCurrency, book: ExchangeRate) -> Decimal? {
        if source.isUSDC, target.code == book.currency.code {
            return book.ask
        }

        if source.code == book.currency.code, target.isUSDC {
            return book.bid
        }

        return nil
    }

    /// Converts an amount between USDc and one quote currency using the supplied book.
    static func convert(
        amount: Decimal,
        from source: AppCurrency,
        to target: AppCurrency,
        book: ExchangeRate
    ) -> Decimal? {
        guard amount >= 0 else { return nil }

        if source.code == target.code {
            return amount
        }

        guard let side = rate(from: source, to: target, book: book) else {
            return nil
        }

        if source.isUSDC {
            return amount * side
        }

        guard side != 0 else { return nil }
        return amount / side
    }

    /// Builds the header copy for the active conversion direction.
    static func rateDescription(
        base: AppCurrency,
        quote: AppCurrency,
        book: ExchangeRate,
        convertingFrom source: AppCurrency,
        to target: AppCurrency
    ) -> String {
        guard let side = rate(from: source, to: target, book: book) else {
            return ""
        }

        let formatted = side.formatted(
            .number
                .locale(Locale(identifier: "en_US"))
                .precision(.fractionLength(2 ... 4))
        )
        return "1 \(base.code) = \(formatted) \(quote.code)"
    }
}
