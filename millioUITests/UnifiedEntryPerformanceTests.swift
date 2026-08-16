import XCTest

final class UnifiedEntryPerformanceTests: XCTestCase {
    private let fixtureEnvironment = [
        "MILLIO_UNIFIED_ENTRY_PERF_MODE": "1"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSyntheticFixtureColdLaunchBaseline() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            let app = XCUIApplication()
            app.launchEnvironment.merge(fixtureEnvironment) { _, new in new }
            app.launch()
        }
    }

    @MainActor
    func testTenIncomeExpenseSwitchesBaseline() {
        let app = XCUIApplication()
        app.launchEnvironment.merge(fixtureEnvironment) { _, new in new }
        app.launch()

        let expense = app.buttons["cashflow.unified.tab.0"]
        let income = app.buttons["cashflow.unified.tab.1"]
        // Local simulator stores can contain residue from unrelated test runs. Fixture
        // replacement is intentionally outside the measured block, so allow it to finish.
        XCTAssertTrue(expense.waitForExistence(timeout: 60))
        XCTAssertTrue(income.exists)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for index in 0..<10 {
                (index.isMultiple(of: 2) ? expense : income).tap()
            }
        }
    }
}
