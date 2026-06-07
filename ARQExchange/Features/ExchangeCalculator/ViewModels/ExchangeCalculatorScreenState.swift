import Foundation

/// Drives calculator header rendering — one explicit state instead of overlapping flags.
enum ExchangeCalculatorScreenState: Equatable {
    case loading
    case ready(rateDescription: String, rateFreshnessLabel: String)
    case failed(message: String)

    var isInteractive: Bool {
        switch self {
        case .loading: false
        case .ready, .failed: true
        }
    }
}
