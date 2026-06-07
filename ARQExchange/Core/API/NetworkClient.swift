import Foundation

/// Transport-level failures emitted before domain-specific API mapping.
enum NetworkError: Error, Sendable {
    case invalidResponse(message: String)
    case httpError(statusCode: Int, message: String)
    case decodingFailed(APIDecodingErrorContext)
}

/// Minimal async JSON client protocol used to inject URLSession-backed and test clients.
protocol NetworkClientProtocol: Sendable {
    /// Executes a request and decodes the response body into the requested payload type.
    func send<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T
}

/// URLSession-backed JSON client with status-code validation and decoding diagnostics.
struct NetworkClient: NetworkClientProtocol, Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(configuration: ARQAPIConfiguration) {
        self.session = configuration.makeURLSession()
        self.decoder = JSONDecoder()
    }

    init(session: URLSession, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    /// Validates the HTTP response and decodes JSON into `T`.
    func send<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        let data = try await sendData(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(
                APIDecodingErrorContext(typeName: String(describing: T.self), error: error)
            )
        }
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(
                message: "Expected an HTTP response but received \(type(of: response))."
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(
                statusCode: httpResponse.statusCode,
                message: "Request failed with HTTP status \(httpResponse.statusCode)."
            )
        }

        return data
    }
}
