import Foundation

/// Actor-backed exchange-rate repository with cache freshness and request coalescing.
///
/// The actor protects mutable cache state, while per-key waiters allow overlapping refreshes
/// for the same currency set to share one network request without one cancelled waiter
/// cancelling the underlying API call for everyone else.
actor ExchangeRateRepository: ExchangeRateRepositoryProtocol {
    private let api: ExchangeRateAPI
    private let maxCacheAge: TimeInterval
    private var cachedRates: [String: ExchangeRate] = [:]
    private var rateLoadedAtByCode: [String: Date] = [:]
    private var inFlightRefreshKeys: Set<String> = []
    private var inFlightRefreshWaiters: [String: [RefreshWaiter]] = [:]

    private struct RefreshWaiter {
        let id: UUID
        let continuation: CheckedContinuation<[ExchangeRate], Error>
    }

    init(
        api: ExchangeRateAPI,
        maxCacheAge: TimeInterval = ARQAPIConfiguration.indicativeRateMaxAge
    ) {
        self.api = api
        self.maxCacheAge = maxCacheAge
    }

    /// Ensures requested quote rates are cached according to the refresh policy.
    func prefetchRates(for currencies: [AppCurrency], policy: RateRefreshPolicy) async throws {
        let selectedQuotes = Self.filterQuoteCurrencies(from: currencies)
        guard !selectedQuotes.isEmpty else { return }

        if case .useCacheIfFresh = policy, hasFreshRates(for: selectedQuotes) {
            return
        }

        try await refreshRates(for: selectedQuotes)
    }

    /// Returns the cached rate when allowed, otherwise refreshes the requested quote.
    func exchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate {
        if currency.isUSDC {
            throw ExchangeRateRepositoryError.missingRate(currency)
        }

        if canUseFreshRate(for: currency, policy: policy), let cached = cachedRates[currency.currencyCode] {
            return cached
        }

        return try await refreshExchangeRate(for: currency, policy: policy)
    }

    /// Refreshes/read-throughs one quote rate and fails if the API response omits it.
    func refreshExchangeRate(for currency: AppCurrency, policy: RateRefreshPolicy) async throws -> ExchangeRate {
        if currency.isUSDC {
            throw ExchangeRateRepositoryError.missingRate(currency)
        }

        if case .useCacheIfFresh = policy,
           canUseFreshRate(for: currency, policy: policy),
           let cached = cachedRates[currency.currencyCode] {
            return cached
        }

        try await refreshRates(for: [currency])

        guard let rate = cachedRates[currency.currencyCode] else {
            throw ExchangeRateRepositoryError.missingRate(currency)
        }

        return rate
    }

    private func hasFreshRates(for currencies: [AppCurrency]) -> Bool {
        currencies.allSatisfy { currency in
            cachedRates[currency.currencyCode] != nil && !isRateStale(for: currency)
        }
    }

    private func canUseFreshRate(for currency: AppCurrency, policy: RateRefreshPolicy) -> Bool {
        switch policy {
        case .useCacheIfFresh:
            return !isRateStale(for: currency)
        case .forceRefresh:
            return false
        }
    }

    private func isRateStale(for currency: AppCurrency) -> Bool {
        guard let loadedAt = rateLoadedAtByCode[currency.currencyCode] else { return true }
        return Date().timeIntervalSince(loadedAt) > maxCacheAge
    }

    /// Performs the network refresh for a normalized quote set, sharing in-flight work by key.
    private func refreshRates(for currencies: [AppCurrency]) async throws {
        let selectedQuotes = Self.filterQuoteCurrencies(from: currencies)
        guard !selectedQuotes.isEmpty else { return }

        let key = Self.refreshKey(for: selectedQuotes)

        if inFlightRefreshKeys.contains(key) {
            let waiterID = UUID()
            _ = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let waiter = RefreshWaiter(id: waiterID, continuation: continuation)
                    inFlightRefreshWaiters[key, default: []].append(waiter)
                }
            } onCancel: { [key, waiterID] in
                Task { await self.cancelRefreshWaiter(id: waiterID, for: key) }
            }
            return
        }

        inFlightRefreshKeys.insert(key)
        defer { inFlightRefreshKeys.remove(key) }

        do {
            let fetched = try await api.fetchTickers(for: selectedQuotes)
            merge(fetched, loadedAt: Date())
            resumeRefreshWaiters(for: key, with: .success(fetched))
        } catch {
            resumeRefreshWaiters(for: key, with: .failure(error))
            throw error
        }
    }

    private func resumeRefreshWaiters(
        for key: String,
        with result: Result<[ExchangeRate], Error>
    ) {
        let waiters = inFlightRefreshWaiters.removeValue(forKey: key) ?? []
        for waiter in waiters {
            switch result {
            case .success(let rates):
                waiter.continuation.resume(returning: rates)
            case .failure(let error):
                waiter.continuation.resume(throwing: error)
            }
        }
    }

    private func cancelRefreshWaiter(id: UUID, for key: String) {
        guard var waiters = inFlightRefreshWaiters[key],
              let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        if waiters.isEmpty {
            inFlightRefreshWaiters.removeValue(forKey: key)
        } else {
            inFlightRefreshWaiters[key] = waiters
        }
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func merge(_ rates: [ExchangeRate], loadedAt: Date) {
        for rate in rates {
            cachedRates[rate.currency.currencyCode] = rate
            rateLoadedAtByCode[rate.currency.currencyCode] = loadedAt
        }
    }

    private nonisolated static func filterQuoteCurrencies(from currencies: [AppCurrency]) -> [AppCurrency] {
        currencies.filter { !$0.isUSDC }
    }

    private nonisolated static func refreshKey(for currencies: [AppCurrency]) -> String {
        filterQuoteCurrencies(from: currencies)
            .map(\.currencyCode)
            .sorted()
            .joined(separator: ",")
    }
}
