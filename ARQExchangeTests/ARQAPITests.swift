import Foundation
import Testing
@testable import ARQExchange

struct ARQAPIEndpointTests {
    @Test func tickersURLUsesAllSupportedCurrencyCodes() throws {
        let configuration = ARQAPIConfiguration.production
        let endpoint = ARQAPIEndpoint.tickers(
            currenciesQuery: SupportedCurrencies.apiTickerCodes
        )

        let url = try endpoint.url(using: configuration)

        #expect(url.absoluteString.hasPrefix("https://api.dolarapp.dev/v1/tickers"))
        #expect(url.query == "currencies=ARS,BRL,COP,MXN")

        for currency in SupportedCurrencies.pickerCurrencies {
            #expect(SupportedCurrencies.apiTickerCodes.contains(currency.isoCode))
        }
    }

    @Test func tickersUsesGET() throws {
        let configuration = ARQAPIConfiguration.production
        let request = try ARQAPIEndpoint
            .tickers(currenciesQuery: "MXN,ARS")
            .urlRequest(using: configuration)

        #expect(request.httpMethod == HTTPMethod.get.rawValue)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func tickerCurrenciesURLMatchesDocumentedEndpoint() throws {
        let configuration = ARQAPIConfiguration.production
        let url = try ARQAPIEndpoint.tickerCurrencies.url(using: configuration)

        #expect(url.absoluteString == "https://api.dolarapp.dev/v1/tickers-currencies")
        #expect(url.query == nil)
    }
}

struct TickerCurrenciesDTOTests {
    @Test func decodesDocumentedStringArrayResponse() throws {
        let json = """
        ["MXN","ARS","BRL","COP"]
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TickerCurrenciesResponse.self, from: json)

        #expect(response.codes == ["MXN", "ARS", "BRL", "COP"])
    }
}

struct ARQAPIErrorTests {
    @Test func decodingErrorIncludesDiagnosticContextWithoutLeakingToUserMessage() throws {
        struct Payload: Decodable, Sendable {
            let ask: Decimal
        }
        let json = """
        {"ask":"not-a-number"}
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(Payload.self, from: json)
        } catch {
            let apiError = ARQAPIError.decodingFailed(
                APIDecodingErrorContext(typeName: "Payload", error: error)
            )
            #expect(apiError.userFacingMessage == "Unable to read the latest exchange rates.")
            #expect(apiError.diagnosticMessage.contains("Failed to decode Payload"))
            #expect(apiError.diagnosticMessage.contains("ask"))
            return
        }

        Issue.record("Expected decoding to fail.")
    }

    @Test func httpErrorProvidesSpecificUserFacingMessage() {
        let error = ARQAPIError.httpError(statusCode: 429)
        #expect(error.userFacingMessage.contains("temporarily busy"))
        #expect(error.diagnosticMessage.contains("HTTP error 429"))
    }
}

struct TickerDTOTests {
    @Test func parsesLiveTickerPayload() throws {
        let json = """
        [
          {"ask":"17.3252200000","bid":"17.3194000000","book":"usdc_mxn","date":"2026-06-04T02:49:11.787427197"},
          {"ask":"1514.9900000000","bid":"1508.0803500000","book":"usdc_ars","date":"2026-06-04T02:49:11.792319456"}
        ]
        """.data(using: .utf8)!

        let dtos = try JSONDecoder().decode([TickerDTO].self, from: json)
        #expect(dtos.count == 2)

        let mxnRate = try dtos[0].toDomain()
        #expect(mxnRate.currency.code == "MXN")
        #expect(mxnRate.ask > 17)
        #expect(mxnRate.bid > 17)

        let mxnUpdatedAt = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: mxnRate.updatedAt
        )
        #expect(mxnUpdatedAt.year == 2026)
        #expect(mxnUpdatedAt.month == 6)
        #expect(mxnUpdatedAt.day == 4)
        #expect(mxnUpdatedAt.hour == 2)
        #expect(mxnUpdatedAt.minute == 49)
        #expect(mxnUpdatedAt.second == 11)

        let arsRate = try dtos[1].toDomain()
        #expect(arsRate.currency.code == "ARS")
    }

    @Test func rejectsInvalidTickerDate() throws {
        let json = """
        [{"ask":"17.32","bid":"17.31","book":"usdc_mxn","date":"not-a-date"}]
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode([TickerDTO].self, from: json)[0]
        #expect(throws: ARQAPIError.self) {
            try dto.toDomain()
        }
    }

    @Test func ignoresNullTickerEntries() throws {
        let json = """
        [
          null,
          {"ask":"17.32","bid":"17.31","book":"usdc_mxn","date":"2026-06-04T02:49:11.787427197"}
        ]
        """.data(using: .utf8)!

        let dtos = try JSONDecoder().decode([TickerDTO?].self, from: json)
        let rates = try dtos.compactMap { $0 }.map { try $0.toDomain() }

        #expect(rates.count == 1)
        #expect(rates[0].currency.code == "MXN")
    }
}

struct SupportedCurrenciesAPITests {
    @Test func pickerListsOnlyLiveTickerCurrencies() {
        #expect(SupportedCurrencies.pickerCurrencies.count == 4)
        #expect(Set(SupportedCurrencies.pickerCurrencies.map(\.code)) == ["ARS", "BRL", "COP", "MXN"])
    }

    @Test func apiTickerCodesMatchesPicker() {
        #expect(SupportedCurrencies.apiTickerCodes == "ARS,BRL,COP,MXN")
    }

    @Test func mapsTickerBookToCurrency() {
        let currency = SupportedCurrencies.fromTickerBook("usdc_mxn")
        #expect(currency?.code == "MXN")
    }
}
