import Foundation

/// Concrete DolarApp API adapter used by the exchange calculator domain layer.
///
/// This type is intentionally thin: endpoint construction and HTTP concerns stay in
/// `ARQAPIEndpoint`/`NetworkClient`, while DTO validation and domain conversion happen here.
struct ARQAPIClient: ExchangeRateAPI, Sendable {
    private let networkClient: NetworkClientProtocol
    private let configuration: ARQAPIConfiguration

    init(
        configuration: ARQAPIConfiguration = .production,
        networkClient: NetworkClientProtocol? = nil
    ) {
        self.configuration = configuration
        self.networkClient = networkClient ?? NetworkClient(configuration: configuration)
    }

    /// Fetches USDC ticker books for the supplied quote currencies.
    ///
    /// USDc itself is filtered out because the API only returns quote books such as
    /// `usdc_mxn`; same-currency conversion is handled locally by the domain layer.
    func fetchTickers(for currencies: [AppCurrency]) async throws -> [ExchangeRate] {
        let codes = currencies
            .filter { !$0.isUSDC }
            .map(\.isoCode)

        guard !codes.isEmpty else { return [] }

        let query = codes.joined(separator: ",")
        return try await fetchTickers(currenciesQuery: query)
    }

    /// Fetches supported quote currency codes from `GET /v1/tickers-currencies`.
    /// Not wired into the app yet — `SupportedCurrencies` is the source of truth until this ships.
    func fetchTickerCurrencies() async throws -> TickerCurrenciesResponse {
        let endpoint = ARQAPIEndpoint.tickerCurrencies
        let request = try endpoint.urlRequest(using: configuration)

        return try await sendAPIRequest(
            request,
            fallbackContext: "tickers-currencies"
        )
    }

    /// Fetches and validates ticker DTOs for a pre-built comma-separated currency query.
    private func fetchTickers(currenciesQuery: String) async throws -> [ExchangeRate] {
        guard !currenciesQuery.isEmpty else { return [] }

        let endpoint = ARQAPIEndpoint.tickers(currenciesQuery: currenciesQuery)
        let request = try endpoint.urlRequest(using: configuration)

        let dtos: [TickerDTO?] = try await sendAPIRequest(
            request,
            fallbackContext: "exchange-rate"
        )

        let rates = try dtos.compactMap { $0 }.map { try $0.toDomain() }
        guard !rates.isEmpty else {
            throw ARQAPIError.invalidResponse(message: "The API response did not contain any usable ticker entries.")
        }
        return rates
    }

    /// Sends a typed API request while preserving internal diagnostics and user-safe errors.
    private func sendAPIRequest<T: Decodable & Sendable>(
        _ request: URLRequest,
        fallbackContext: String
    ) async throws -> T {
        do {
            return try await networkClient.send(request)
        } catch let error as NetworkError {
            throw ARQAPIError.map(error)
        } catch let error as ARQAPIError {
            throw error
        } catch {
            throw ARQAPIError.invalidResponse(
                message: "The \(fallbackContext) request failed before a valid API response was received: \(error.localizedDescription)"
            )
        }
    }
}
