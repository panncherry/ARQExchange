import SwiftUI

enum AppDependencies {
    static func makeExchangeCalculatorViewModel() -> ExchangeCalculatorViewModel {
        if ProcessInfo.processInfo.arguments.contains("-UITestingMockData") {
            return ExchangeCalculatorViewModel(repository: MockExchangeRateRepository())
        }

        let configuration = ARQAPIConfiguration.production
        let apiClient = ARQAPIClient(configuration: configuration)
        let repository = ExchangeRateRepository(api: apiClient)
        return ExchangeCalculatorViewModel(repository: repository)
    }
}
