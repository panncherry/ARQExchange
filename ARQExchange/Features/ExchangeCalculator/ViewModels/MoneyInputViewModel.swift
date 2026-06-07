import Foundation

/// Observable amount model that stores user input in minor units.
///
/// Keeping integer minor units avoids floating-point drift while typing and allows the
/// UI to reject values that would exceed app-defined transfer/display limits.
@MainActor
@Observable
final class MoneyInputViewModel {
    private(set) var minorUnits: Int64 = 0

    let currency: AppCurrency
    private let minorUnitsDivisor: Decimal

    init(currency: AppCurrency, minorUnits: Int64 = 0) {
        self.currency = currency
        self.minorUnits = minorUnits
        let places = currency.decimalPlaces
        minorUnitsDivisor = Decimal(pow(10.0, Double(places)))
    }

    /// Localized display value for the current minor-unit amount.
    var formattedAmount: String {
        currency.formattedAmount(minorUnits: minorUnits)
    }

    var decimalAmount: Decimal {
        Decimal(minorUnits) / minorUnitsDivisor
    }

    var isAtLimit: Bool {
        guard let maxMinorUnits = currency.maxMinorUnits, minorUnits > 0 else { return false }
        return minorUnits >= maxMinorUnits
    }

    func setMinorUnits(_ value: Int64) {
        minorUnits = clampedMinorUnits(max(0, value))
    }

    func insertDigit(_ digit: Int) {
        guard (0 ... 9).contains(digit) else { return }
        guard minorUnits <= (Int64.max - Int64(digit)) / 10 else { return }

        let nextValue = minorUnits * 10 + Int64(digit)
        guard !exceedsMaxMinorUnits(nextValue) else { return }

        minorUnits = nextValue
    }

    func deleteBackward() {
        minorUnits /= 10
    }

    func reset() {
        minorUnits = 0
    }

    /// Applies raw keyboard text after digit filtering and limit validation.
    ///
    /// Returns `false` without mutating state when the proposed amount would exceed
    /// the currency limit or cannot be represented by `Int64`.
    @discardableResult
    func applyKeyboardDigits(_ text: String) -> Bool {
        let filtered = String(text.filter(\.isWholeNumber).prefix(Self.maxInputDigits))

        guard !filtered.isEmpty else {
            minorUnits = 0
            return true
        }

        guard let value = Int64(filtered) else {
            return false
        }

        guard !exceedsMaxMinorUnits(value) else {
            return false
        }

        minorUnits = value
        return true
    }

    func restoreMinorUnits(_ value: Int64) {
        minorUnits = max(0, value)
    }

    var keyboardDigits: String {
        minorUnits == 0 ? "" : String(minorUnits)
    }

    /// Stores a converted decimal amount after rounding to the target currency scale.
    func applyConvertedAmount(_ amount: Decimal) {
        guard let minorUnits = Self.minorUnits(for: amount, currency: currency) else {
            return
        }

        self.minorUnits = minorUnits
    }

    static func minorUnits(for amount: Decimal, currency: AppCurrency) -> Int64? {
        let multiplier = Decimal(pow(10.0, Double(currency.decimalPlaces)))
        var scaled = amount * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)

        guard let maxMinorUnits = currency.maxMinorUnits else {
            return max(0, NSDecimalNumber(decimal: rounded).int64Value)
        }

        let int64Max = Decimal(Int64.max)
        if rounded < 0 {
            return 0
        }
        if rounded > Decimal(maxMinorUnits) {
            return nil
        }
        if rounded > int64Max {
            return Int64.max
        }

        return NSDecimalNumber(decimal: rounded).int64Value
    }

    private static let maxInputDigits = 18

    private func exceedsMaxMinorUnits(_ value: Int64) -> Bool {
        guard let maxMinorUnits = currency.maxMinorUnits else { return false }
        return value > maxMinorUnits
    }

    private func clampedMinorUnits(_ value: Int64) -> Int64 {
        var clamped = max(0, value)
        if let maxMinorUnits = currency.maxMinorUnits {
            clamped = min(clamped, maxMinorUnits)
        }
        return clamped
    }

}
