import Foundation

struct AppRuntimeEnvironment: Equatable {
    let isUnitTesting: Bool
    let isUITesting: Bool
    /// Режим автоматической генерации App Store скриншотов.
    /// Активируется env var MILLIO_SCREENSHOT_MODE=1 из fastlane snapshot UI-тестов.
    let isScreenshotMode: Bool

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppRuntimeEnvironment {
        AppRuntimeEnvironment(
            isUnitTesting: environment["XCTestConfigurationFilePath"] != nil,
            isUITesting: environment["MILLIO_UI_TEST_MODE"] == "1",
            isScreenshotMode: environment["MILLIO_SCREENSHOT_MODE"] == "1"
        )
    }

    var isAnyTesting: Bool {
        isUnitTesting || isUITesting || isScreenshotMode
    }
}
