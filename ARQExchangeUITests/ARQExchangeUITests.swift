import XCTest

final class ARQExchangeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCalculatorScreenLoads() throws {
        let app = launchApp()

        XCTAssertTrue(app.otherElements["appReady"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.staticTexts["Exchange calculator"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["currencyInputCard"].firstMatch.exists)
        XCTAssertTrue(inputRow(in: app, identifier: "topInputRow").exists)
    }

    @MainActor
    func testEnteringAmountUpdatesConvertedValue() throws {
        let app = launchApp()
        waitForAppReady(app)

        typeAmount("99999", in: app, row: "topInputRow")

        let bottomAmount = app.staticTexts["bottomAmountLabel"]
        XCTAssertTrue(bottomAmount.waitForExistence(timeout: 2))
        XCTAssertFalse(bottomAmount.label.contains("$0.00"))
    }

    @MainActor
    func testCurrencyPickerSelection() throws {
        let app = launchApp()
        waitForAppReady(app)

        currencyButton(in: app, identifier: "bottomCurrencyButton").tap()
        let pickerSheet = app.descendants(matching: .any)["currencyPickerSheet"].firstMatch
        XCTAssertTrue(pickerSheet.waitForExistence(timeout: 2))

        let copOption = app.staticTexts["COP"]
        XCTAssertTrue(copOption.waitForExistence(timeout: 2))
        copOption.tap()

        let rateDescription = app.staticTexts["rateDescription"]
        XCTAssertTrue(rateDescription.waitForExistence(timeout: 5))
        XCTAssertTrue(rateDescription.label.contains("COP"))
    }

    @MainActor
    func testSwapCurrencies() throws {
        let app = launchApp()
        waitForAppReady(app)

        typeAmount("10000", in: app, row: "topInputRow")
        app.buttons["keyboardDoneButton"].tap()
        app.buttons["swapButton"].tap()

        XCTAssertTrue(currencyButton(in: app, identifier: "topCurrencyButton").label.contains("MXN"))
        XCTAssertTrue(currencyButton(in: app, identifier: "bottomCurrencyButton").label.contains("USDc"))
        XCTAssertTrue(inputRow(in: app, identifier: "bottomInputRow").exists)
        XCTAssertTrue(app.staticTexts["bottomAmountLabel"].label.contains("100.00"))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingMockData"]
        app.launch()
        return app
    }

    @MainActor
    private func waitForAppReady(_ app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["appReady"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func typeAmount(_ amount: String, in app: XCUIApplication, row identifier: String) {
        inputRow(in: app, identifier: identifier).tap()
        app.typeText(amount)
    }

    @MainActor
    private func inputRow(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        return element
    }

    /// Quote rows use `Button`; USDc uses a plain label with the same accessibility identifier.
    @MainActor
    private func currencyButton(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        return element
    }
}
