import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct BackendStartupResolverTests {
    private let deURL = URL(string: "https://api.udzutech.com/api/v1")!
    private let altURL = URL(string: "https://alt.example.com/api/v1")!

    @Test("RU country now resolves to the single DE backend")
    func testRUCountrySelectsSingleBackend() async {
        URLProtocolBackendStub.setHandler { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://api.udzutech.com/api/v1/runtime/server-info")
            return Self.successResponse(
                url: url,
                region: "DE",
                publicApiBaseURL: "https://api.udzutech.com/api/v1"
            )
        }
        defer { URLProtocolBackendStub.reset() }

        let runtime = await makeResolver(countryCode: "RU").resolve()

        #expect(runtime.selectedEndpoint.region == .de)
        #expect(runtime.selectedEndpoint.baseURL == deURL)
        #expect(runtime.fallbackActivated == false)
        #expect(runtime.selectionSource == .automaticLocale)
        #expect(runtime.detectedCountryCode == "RU")
    }

    @Test(
        "Non-RU and unknown countries select DE backend",
        arguments: ["DE", "FR", "NL", "US", nil]
    )
    func testNonRUCountrySelectsDEBackend(countryCode: String?) async {
        URLProtocolBackendStub.setHandler { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://api.udzutech.com/api/v1/runtime/server-info")
            return Self.successResponse(
                url: url,
                region: "DE",
                publicApiBaseURL: "https://api.udzutech.com/api/v1"
            )
        }
        defer { URLProtocolBackendStub.reset() }

        let runtime = await makeResolver(countryCode: countryCode).resolve()

        #expect(runtime.selectedEndpoint.region == .de)
        #expect(runtime.selectedEndpoint.baseURL == deURL)
        #expect(runtime.fallbackActivated == false)
        #expect(runtime.selectionSource == .automaticLocale)
    }

    @Test("Keeps single backend when probe fails because there is no secondary host anymore")
    func testProbeFailureKeepsSingleBackend() async {
        URLProtocolBackendStub.setHandler { request in
            _ = try #require(request.url)
            throw URLError(.cannotConnectToHost)
        }
        defer { URLProtocolBackendStub.reset() }

        let runtime = await makeResolver(countryCode: "RU").resolve()

        #expect(runtime.selectedEndpoint.region == .de)
        #expect(runtime.preferredEndpoint.region == .de)
        #expect(runtime.selectedEndpoint.baseURL == deURL)
        #expect(runtime.fallbackActivated == false)
        #expect(runtime.selectionSource == .automaticLocale)
    }

    @Test("Preferred language region is used when locale region is missing")
    func testSystemCountryCodeResolverFallsBackToPreferredLanguageRegion() {
        let resolved = SystemCountryCodeResolver.resolve(
            autoupdatingLocale: Locale(identifier: "en"),
            currentLocale: Locale(identifier: "fr"),
            preferredLanguages: ["ru-RU", "en-US"]
        )

        #expect(resolved == "RU")
    }

    @Test("Production defaults are used when endpoint config is missing")
    func testBackendEndpointsLiveFallsBackToProductionDefaults() throws {
        let endpoints = try BackendEndpoints.live(
            environment: [:],
            infoDictionary: [:]
        )

        #expect(endpoints.ru.baseURL.absoluteString == "https://api.udzutech.com/api/v1")
        #expect(endpoints.de.baseURL.absoluteString == "https://api.udzutech.com/api/v1")
    }

    @Test("Unresolved plist placeholders fall back to production defaults")
    func testBackendEndpointsLiveIgnoresUnresolvedPlaceholders() throws {
        let endpoints = try BackendEndpoints.live(
            environment: [:],
            infoDictionary: [
                "RU_API_BASE_URL": "$(RU_API_BASE_URL)",
                "DE_API_BASE_URL": "$(DE_API_BASE_URL)"
            ]
        )

        #expect(endpoints.ru.baseURL.absoluteString == "https://api.udzutech.com/api/v1")
        #expect(endpoints.de.baseURL.absoluteString == "https://api.udzutech.com/api/v1")
    }

    @Test("Auth tokens are isolated between different backend namespaces")
    func testAuthTokensAreIsolatedBetweenBackends() throws {
        let primaryRuntime = BackendSessionRuntime(
            selectedEndpoint: BackendEndpoint(region: .de, baseURL: deURL),
            preferredEndpoint: BackendEndpoint(region: .de, baseURL: deURL),
            fallbackActivated: false,
            forcedOverride: false,
            selectionSource: .automaticLocale,
            detectedCountryCode: "DE"
        )
        let alternateRuntime = BackendSessionRuntime(
            selectedEndpoint: BackendEndpoint(region: .de, baseURL: altURL),
            preferredEndpoint: BackendEndpoint(region: .de, baseURL: altURL),
            fallbackActivated: false,
            forcedOverride: false,
            selectionSource: .automaticLocale,
            detectedCountryCode: "US"
        )

        let backend = InMemoryAccountTokenBackend()
        let primaryStore = AccountScopedRefreshTokenStore(
            account: primaryRuntime.refreshTokenAccountKey,
            backend: backend
        )
        let alternateStore = AccountScopedRefreshTokenStore(
            account: alternateRuntime.refreshTokenAccountKey,
            backend: backend
        )

        try primaryStore.setRefreshToken("primary-refresh")
        #expect(try primaryStore.refreshToken() == "primary-refresh")
        #expect(try alternateStore.refreshToken() == nil)

        try alternateStore.setRefreshToken("alternate-refresh")
        #expect(try primaryStore.refreshToken() == "primary-refresh")
        #expect(try alternateStore.refreshToken() == "alternate-refresh")

        try primaryStore.clearRefreshToken()
        #expect(try primaryStore.refreshToken() == nil)
        #expect(try alternateStore.refreshToken() == "alternate-refresh")
    }

    @Test("Configuration fallback summary is explicit")
    func testConfigurationFallbackSummary() {
        let runtime = BackendSessionRuntime(
            selectedEndpoint: BackendEndpoint(region: .de, baseURL: deURL),
            preferredEndpoint: BackendEndpoint(region: .de, baseURL: deURL),
            fallbackActivated: false,
            forcedOverride: false,
            selectionSource: .configurationFallback,
            detectedCountryCode: "RU"
        )

        #expect(runtime.selectionSummaryLine == "Selection: Config fallback (RU)")
    }

    private func makeResolver(countryCode: String?) -> BackendStartupResolver {
        BackendStartupResolver(
            endpoints: BackendEndpoints(
                ru: BackendEndpoint(region: .ru, baseURL: deURL),
                de: BackendEndpoint(region: .de, baseURL: deURL)
            ),
            session: makeSession(),
            countryCodeProvider: { countryCode },
            forcedEndpointProvider: { _ in nil }
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolBackendStub.self]
        return URLSession(configuration: configuration)
    }

    private static func successResponse(
        url: URL,
        region: String,
        publicApiBaseURL: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let data = Data(
            """
            {
              "region": "\(region)",
              "publicApiBaseUrl": "\(publicApiBaseURL)"
            }
            """.utf8
        )
        return (response, data)
    }
}

private final class URLProtocolBackendStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class InMemoryAccountTokenBackend: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func read(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func write(_ value: String, account: String) {
        lock.lock()
        values[account] = value
        lock.unlock()
    }

    func delete(account: String) {
        lock.lock()
        values[account] = nil
        lock.unlock()
    }
}

private struct AccountScopedRefreshTokenStore: RefreshTokenStoreProtocol {
    let account: String
    let backend: InMemoryAccountTokenBackend

    func refreshToken() throws -> String? {
        backend.read(account: account)
    }

    func setRefreshToken(_ value: String) throws {
        backend.write(value, account: account)
    }

    func clearRefreshToken() throws {
        backend.delete(account: account)
    }
}
