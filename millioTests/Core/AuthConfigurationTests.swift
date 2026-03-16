import Foundation
import Testing
@testable import millio

struct AuthConfigurationTests {
    @Test("live prefers DE API base URL as the default runtime backend")
    func testLivePrefersDEAPIBaseURL() throws {
        let configuration = try AuthConfiguration.live(
            environment: [
            "DE_API_BASE_URL": "https://api.iqdrop.ru/api/v1/"
            ].compactMapValues { $0 },
            infoDictionary: [:]
        )

        #expect(configuration.baseURL.absoluteString == "https://api.iqdrop.ru/api/v1")
        #expect(configuration.region == .de)
    }

    @Test("live still supports explicit legacy auth base URL override")
    func testLivePrefersEnvironmentBaseURL() throws {
        let configuration = try AuthConfiguration.live(
            environment: [
            "AUTH_BASE_URL": "https://example.com/custom/",
            ].compactMapValues { $0 },
            infoDictionary: [:]
        )

        #expect(configuration.baseURL.absoluteString == "https://example.com/custom")
    }

    @Test("live falls back to production DE URL when DE endpoint is unresolved")
    func testLiveFallsBackToProductionDEURLForUnresolvedPlaceholder() throws {
        let configuration = try AuthConfiguration.live(
            environment: [:],
            infoDictionary: [
                "DE_API_BASE_URL": "$(DE_API_BASE_URL)"
            ]
        )

        #expect(configuration.baseURL.absoluteString == "https://api.iqdrop.ru/api/v1")
        #expect(configuration.region == .de)
    }
}
