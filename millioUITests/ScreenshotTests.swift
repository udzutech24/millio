//
//  ScreenshotTests.swift
//  millioUITests
//
//  Автоматические App Store скриншоты через fastlane snapshot.
//  Запуск: bundle exec fastlane screenshots
//
//  Перед первым запуском добавь SnapshotHelper.swift в этот таргет:
//  bundle exec fastlane snapshot init
//

import XCTest

final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 1. Finances — accounts list

    @MainActor
    func testScreenshot01Finances() {
        let app = makeApp()
        setupSnapshot(app)
        app.launch()

        waitForMainUI(app)
        tap(app, id: "tab.finances")
        sleep(2)
        snapshot("01-finances")
    }

    // MARK: - 2. Finances Dynamics — chart

    @MainActor
    func testScreenshot02Dynamics() {
        let app = makeApp()
        setupSnapshot(app)
        app.launch()

        waitForMainUI(app)
        tap(app, id: "tab.dynamics")
        sleep(2)
        snapshot("02-dynamics")
    }

    // MARK: - 3. Cashflow

    @MainActor
    func testScreenshot03Cashflow() {
        let app = makeApp()
        setupSnapshot(app)
        app.launch()

        waitForMainUI(app)
        tap(app, id: "tab.cashflow")
        sleep(2)
        snapshot("03-cashflow")
    }

    @MainActor
    func testScreenshot08CashflowMonth() {
        let app = makeApp()
        setupSnapshot(app)
        app.launch()

        waitForMainUI(app)
        tap(app, id: "tab.cashflow")
        tap(app, id: "cashflow.action.month")
        sleep(2)
        snapshot("08-cashflow-month")
    }

    // MARK: - 4. Rates (Courses)

    @MainActor
    func testScreenshot04Rates() {
        let app = makeApp()
        setupSnapshot(app)
        app.launch()

        waitForMainUI(app)
        tap(app, id: "dashboard.chip.courses")
        sleep(2)
        snapshot("04-rates")
    }

    // MARK: - 5. Cashback

    @MainActor
    func testScreenshot05Cashback() {
        let app = makeApp()
        setupSnapshot(app)
        app.launch()

        waitForMainUI(app)
        tap(app, id: "dashboard.chip.cashback")
        sleep(2)
        snapshot("05-cashback")
    }

    // MARK: - 6. Dashboard

    @MainActor
    func testScreenshot06Dashboard() {
        let app = makeApp()
        setupSnapshot(app)
        app.launch()

        waitForMainUI(app)
        tap(app, id: "tab.dashboard")
        sleep(2)
        snapshot("06-dashboard")
    }

    // MARK: - 7. Backup

    @MainActor
    func testScreenshot07Backup() {
        let app = makeApp()
        setupSnapshot(app)
        app.launch()

        waitForMainUI(app)
        tap(app, id: "root.profileButton")
        sleep(2)
        tap(app, id: "profile.backupLink")
        sleep(4)
        snapshot("07-backup")
    }

    // MARK: - Helpers

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MILLIO_SCREENSHOT_MODE"] = "1"
        return app
    }

    private func waitForMainUI(_ app: XCUIApplication, timeout: TimeInterval = 8) {
        let tabBar = app.buttons["tab.dashboard"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: timeout), "Tab bar did not appear")
    }

    private func tap(_ app: XCUIApplication, id: String, timeout: TimeInterval = 5) {
        let element = app.buttons[id]
        if element.waitForExistence(timeout: timeout) {
            element.tap()
        }
    }
}
