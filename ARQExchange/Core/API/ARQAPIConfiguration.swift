import Foundation

/// Configuration profile for DolarApp exchange-rate API requests.
///
/// Keeps transport-level decisions in one place so production, testing, and preview
/// clients can share the same endpoint construction while varying timeouts or base URLs.
struct ARQAPIConfiguration {
    /// Base API URL, including the `/v1` path segment used by all endpoints.
    let baseURL: URL
    /// Per-request timeout applied to both `URLRequest` and the backing `URLSession`.
    let requestTimeout: TimeInterval
    /// Maximum time a request may spend loading all resources before the session fails it.
    let resourceTimeout: TimeInterval
    /// Explicit user agent sent with API requests for service-side diagnostics.
    let userAgent: String
    /// Optional bearer token provider for authenticated API requests.
    let bearerTokenProvider: (@Sendable () async throws -> String?)?

    init(
        baseURL: URL,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        userAgent: String,
        bearerTokenProvider: (@Sendable () async throws -> String?)? = nil
    ) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.userAgent = userAgent
        self.bearerTokenProvider = bearerTokenProvider
    }

    /// Max age for indicative (calculator) rates before a background refresh runs.
    nonisolated static let indicativeRateMaxAge: TimeInterval = 30

    /// How often to poll for new indicative rates while the calculator screen is visible.
    nonisolated static let indicativeRateRefreshInterval: TimeInterval = 30

    /// Production API configuration used by the app outside UI-test mode.
    static let production = ARQAPIConfiguration(
        baseURL: URL(string: "https://api.dolarapp.dev/v1")!,
        requestTimeout: 30,
        resourceTimeout: 60,
        userAgent: "ARQExchange/1.0"
    )

    /// Session configuration tuned for short-lived JSON API calls.
    var urlSessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": userAgent
        ]
        return configuration
    }

    /// Shared session for all API clients using this configuration profile.
    func makeURLSession() -> URLSession {
        Self.sharedSession(for: self)
    }

    private static let sessionCache = SessionCache()

    private static func sharedSession(for configuration: ARQAPIConfiguration) -> URLSession {
        sessionCache.session(for: configuration)
    }
}

/// Thread-safe URLSession cache keyed by transport configuration.
///
/// URLSession instances are relatively expensive and safe to reuse, so production code
/// shares one per configuration instead of creating a new session for every API client.
private final class SessionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [SessionCacheKey: URLSession] = [:]

    func session(for configuration: ARQAPIConfiguration) -> URLSession {
        let key = SessionCacheKey(configuration: configuration)
        lock.lock()
        defer { lock.unlock() }

        if let existing = sessions[key] {
            return existing
        }

        let session = URLSession(configuration: configuration.urlSessionConfiguration)
        sessions[key] = session
        return session
    }
}

private struct SessionCacheKey: Hashable {
    let baseURL: URL
    let requestTimeout: TimeInterval
    let resourceTimeout: TimeInterval
    let userAgent: String

    init(configuration: ARQAPIConfiguration) {
        baseURL = configuration.baseURL
        requestTimeout = configuration.requestTimeout
        resourceTimeout = configuration.resourceTimeout
        userAgent = configuration.userAgent
    }
}
