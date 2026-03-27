import Foundation

struct AppRuntimeEnvironment: Equatable {
    let isUnitTesting: Bool
    let isUITesting: Bool

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppRuntimeEnvironment {
        AppRuntimeEnvironment(
            isUnitTesting: environment["XCTestConfigurationFilePath"] != nil,
            isUITesting: environment["MILLIO_UI_TEST_MODE"] == "1"
        )
    }

    var isAnyTesting: Bool {
        isUnitTesting || isUITesting
    }
}
