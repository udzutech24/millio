import XCTest

final class DebitCardRenderBootstrapUITests: XCTestCase {
    @MainActor
    func testLaunchesDebitHarnessAndHandlesNotificationPrompt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MILLIO_DEBIT_CARD_QA"] = "1"
        app.launchEnvironment["MILLIO_DEBIT_QA_MODE"] = "positive"
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            for label in ["Allow", "Разрешить", "允许"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
