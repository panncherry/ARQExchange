import Foundation

/// Controls whether cached ticker data may be returned or a network refresh is required.
enum RateRefreshPolicy: Sendable {
    /// Return cache when younger than `indicativeRateMaxAge`; otherwise fetch.
    case useCacheIfFresh
    /// Always fetch latest tickers (e.g. foreground, transfer review).
    case forceRefresh
}

extension RateRefreshPolicy: Equatable {
    nonisolated static func == (lhs: RateRefreshPolicy, rhs: RateRefreshPolicy) -> Bool {
        switch (lhs, rhs) {
        case (.useCacheIfFresh, .useCacheIfFresh), (.forceRefresh, .forceRefresh):
            true
        default:
            false
        }
    }

    /// Prefer the stricter policy when coalescing overlapping refreshes.
    nonisolated func merged(with other: Self) -> Self {
        switch (self, other) {
        case (.forceRefresh, _), (_, .forceRefresh): .forceRefresh
        default: .useCacheIfFresh
        }
    }
}
