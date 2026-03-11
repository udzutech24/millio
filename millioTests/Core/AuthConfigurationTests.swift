import Foundation
import Testing
@testable import millio

struct AuthConfigurationTests {
    @Test("live builds base URL from split auth settings")
    func testLiveBuildsURLFromComponents() throws {
        let configuration = try AuthConfiguration.live(
            environment: [
            "AUTH_BASE_URL": nil,
            "AUTH_BASE_SCHEME": "https",
            "AUTH_BASE_HOST": "api.udzutech.com",
            "AUTH_BASE_PORT": nil,
            "AUTH_BASE_PATH": "/api/v1/"
            ].compactMapValues { $0 },
            infoDictionary: [:]
        )

        #expect(configuration.baseURL.absoluteString == "https://api.udzutech.com/api/v1")
    }

    @Test("live prefers full base URL from environment")
    func testLivePrefersEnvironmentBaseURL() throws {
        let configuration = try AuthConfiguration.live(
            environment: [
            "AUTH_BASE_URL": "https://example.com/custom/",
            "AUTH_BASE_SCHEME": "http",
            "AUTH_BASE_HOST": "localhost",
            "AUTH_BASE_PORT": "3000",
            "AUTH_BASE_PATH": "/api/v1"
            ].compactMapValues { $0 },
            infoDictionary: [:]
        )

        #expect(configuration.baseURL.absoluteString == "https://example.com/custom")
    }
}
