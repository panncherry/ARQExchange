import Foundation

enum AmountField: Equatable, Sendable {
    case top
    case bottom

    var accessibilityPrefix: String {
        switch self {
        case .top: "top"
        case .bottom: "bottom"
        }
    }
}
