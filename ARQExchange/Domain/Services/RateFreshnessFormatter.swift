import Foundation

/// Produces compact freshness labels for indicative calculator rates.
enum RateFreshnessFormatter {
    private static let updatedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Returns `Live rate` for recent updates, otherwise a timestamp-based fallback.
    static func indicativeLabel(updatedAt: Date, now: Date = Date()) -> String {
        let age = now.timeIntervalSince(updatedAt)
        if age < 90 {
            return "Live rate"
        }
        return "Updated \(updatedTimeFormatter.string(from: updatedAt))"
    }
}
