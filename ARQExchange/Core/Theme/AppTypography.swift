import SwiftUI

enum AppFontDesign {
    static let headline = Font.system(.headline, design: .default).weight(.semibold)
    static let body = Font.system(.body, design: .default)
    static let bodyBold = Font.system(.body, design: .default).weight(.bold)
    static let bodySemiBold = Font.system(.body, design: .default).weight(.semibold)
    static let footnote = Font.system(.footnote, design: .default)
}

