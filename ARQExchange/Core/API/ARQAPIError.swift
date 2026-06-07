import Foundation

/// Captures decoding context for diagnostics without exposing raw parser details to users.
struct APIDecodingErrorContext: Sendable {
    let typeName: String
    let debugDescription: String
    let codingPath: [String]
    let underlyingDescription: String?

    var pathDescription: String {
        guard !codingPath.isEmpty else { return "<root>" }
        return codingPath.joined(separator: ".")
    }

    /// Developer-facing detail suitable for logs or test assertions, not direct UI display.
    var diagnosticMessage: String {
        var components = [
            "Failed to decode \(typeName)",
            "path: \(pathDescription)",
            debugDescription
        ]

        if let underlyingDescription {
            components.append("underlying: \(underlyingDescription)")
        }

        return components.joined(separator: " | ")
    }

    init(typeName: String, debugDescription: String, codingPath: [String], underlyingDescription: String? = nil) {
        self.typeName = typeName
        self.debugDescription = debugDescription
        self.codingPath = codingPath
        self.underlyingDescription = underlyingDescription
    }

    init(typeName: String, error: Error) {
        self.typeName = typeName

        if let decodingError = error as? DecodingError {
            let context = decodingError.context
            self.debugDescription = context.debugDescription
            self.codingPath = context.codingPath.map(Self.describe)
            self.underlyingDescription = context.underlyingError?.localizedDescription
        } else {
            self.debugDescription = error.localizedDescription
            self.codingPath = []
            self.underlyingDescription = nil
        }
    }

    private nonisolated static func describe(_ key: CodingKey) -> String {
        if let intValue = key.intValue {
            return "[\(intValue)]"
        }
        return key.stringValue
    }
}

/// Domain-specific API error with separate diagnostic and user-facing messages.
enum ARQAPIError: Error, Sendable {
    case invalidURL(message: String = "The API request URL could not be created.")
    case invalidResponse(message: String)
    case httpError(statusCode: Int, message: String)
    case decodingFailed(APIDecodingErrorContext)
}

extension ARQAPIError {
    static var invalidResponse: ARQAPIError {
        .invalidResponse(message: "The API returned an invalid response.")
    }

    static func httpError(statusCode: Int) -> ARQAPIError {
        .httpError(statusCode: statusCode, message: "The API returned HTTP \(statusCode).")
    }

    /// Converts transport failures into API-layer errors consumed by repositories/view models.
    static func map(_ error: NetworkError) -> ARQAPIError {
        switch error {
        case let .invalidResponse(message):
            .invalidResponse(message: message)
        case let .httpError(statusCode, message):
            .httpError(statusCode: statusCode, message: message)
        case let .decodingFailed(context):
            .decodingFailed(context)
        }
    }
}

extension ARQAPIError: LocalizedError {
    var errorDescription: String? {
        userFacingMessage
    }

    /// Copy that is safe to show in the calculator UI.
    var userFacingMessage: String {
        switch self {
        case .invalidURL:
            "Unable to prepare the exchange-rate request."
        case .invalidResponse, .decodingFailed:
            "Unable to read the latest exchange rates."
        case let .httpError(statusCode, _):
            switch statusCode {
            case 401, 403:
                "Unable to access exchange rates right now."
            case 429:
                "Exchange-rate updates are temporarily busy. Please try again shortly."
            case 500...599:
                "The exchange-rate service is temporarily unavailable."
            default:
                "Unable to load exchange rates."
            }
        }
    }

    var diagnosticMessage: String {
        switch self {
        case let .invalidURL(message):
            "Invalid URL: \(message)"
        case let .invalidResponse(message):
            "Invalid response: \(message)"
        case let .httpError(statusCode, message):
            "HTTP error \(statusCode): \(message)"
        case let .decodingFailed(context):
            context.diagnosticMessage
        }
    }
}

private extension DecodingError {
    var context: Context {
        switch self {
        case let .typeMismatch(_, context),
             let .valueNotFound(_, context),
             let .keyNotFound(_, context),
             let .dataCorrupted(context):
            return context
        @unknown default:
            return Context(codingPath: [], debugDescription: localizedDescription)
        }
    }
}

