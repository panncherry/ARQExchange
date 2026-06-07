import Foundation

/// Typed routes for the ARQ tickers API (`/v1`).
enum ARQAPIEndpoint: Equatable, Sendable {
    /// `GET /tickers?currencies=MXN,ARS,...` — USDC quote books per currency.
    case tickers(currenciesQuery: String)
    /// `GET /tickers-currencies` — supported quote currency codes (not yet live).
    case tickerCurrencies

    var method: HTTPMethod { .get }

    var path: String {
        switch self {
        case .tickers: "tickers"
        case .tickerCurrencies: "tickers-currencies"
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case let .tickers(currenciesQuery):
            let value = currenciesQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return [URLQueryItem(name: "currencies", value: value)]
        case .tickerCurrencies:
            return nil
        }
    }

    func url(using configuration: ARQAPIConfiguration) throws -> URL {
        guard var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw ARQAPIError.invalidURL()
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ARQAPIError.invalidURL()
        }
        return url
    }

    func urlRequest(using configuration: ARQAPIConfiguration) throws -> URLRequest {
        var request = URLRequest(url: try url(using: configuration))
        request.httpMethod = method.rawValue
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
