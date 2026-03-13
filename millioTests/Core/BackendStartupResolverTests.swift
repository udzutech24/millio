import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct BackendStartupResolverTests {
    private let ruURL = URL(string: "https://apiru.udzutech.com/api/v1")!
    private let deURL = URL(string: "https://api.udzutech.com/api/v1")!

    @Test("RU country selects RU backend")
    func testRUCountrySelectsRUBackend() async {
        URLProtocolBackendStub.setHandler { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://apiru.udzutech.com/api/v1/runtime/server-info")
            return Self.successResponse(
                url: url,
                region: "RU",
                publicApiBaseURL: "https://apiru.udzutech.com/api/v1"
            )
        }
        defer { URLProtocolBackendStub.reset() }

        let runtime = await makeResolver(countryCode: "RU").resolve()

        #expect(runtime.selectedEndpoint.region == .ru)
        #expect(runtime.selectedEndpoint.baseURL == ruURL)
        #expect(runtime.fallbackActivated == false)
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
    }

    @Test("Falls back to secondary backend when preferred backend is down")
    func testFallbackToSecondaryBackend() async {
        URLProtocolBackendStub.setHandler { request in
            let url = try #require(request.url)
            if url.host() == "apiru.udzutech.com" {
                throw URLError(.cannotConnectToHost)
            }
            return Self.successResponse(
                url: url,
                region: "DE",
                publicApiBaseURL: "https://api.udzutech.com/api/v1"
            )
        }
        defer { URLProtocolBackendStub.reset() }

        let runtime = await makeResolver(countryCode: "RU").resolve()

        #expect(runtime.preferredEndpoint.region == .ru)
        #expect(runtime.selectedEndpoint.region == .de)
        #expect(runtime.selectedEndpoint.baseURL == deURL)
        #expect(runtime.fallbackActivated)
    }

    @Test("Auth tokens are isolated between RU and DE backends")
    func testAuthTokensAreIsolatedBetweenBackends() throws {
        let ruRuntime = BackendSessionRuntime(
            selectedEndpoint: BackendEndpoint(region: .ru, baseURL: ruURL),
            preferredEndpoint: BackendEndpoint(region: .ru, baseURL: ruURL),
            fallbackActivated: false,
            forcedOverride: false
        )
        let deRuntime = BackendSessionRuntime(
            selectedEndpoint: BackendEndpoint(region: .de, baseURL: deURL),
            preferredEndpoint: BackendEndpoint(region: .de, baseURL: deURL),
            fallbackActivated: false,
            forcedOverride: false
        )

        let backend = InMemoryAccountTokenBackend()
        let ruStore = AccountScopedRefreshTokenStore(
            account: ruRuntime.refreshTokenAccountKey,
            backend: backend
        )
        let deStore = AccountScopedRefreshTokenStore(
            account: deRuntime.refreshTokenAccountKey,
            backend: backend
        )

        try ruStore.setRefreshToken("ru-refresh")
        #expect(try ruStore.refreshToken() == "ru-refresh")
        #expect(try deStore.refreshToken() == nil)

        try deStore.setRefreshToken("de-refresh")
        #expect(try ruStore.refreshToken() == "ru-refresh")
        #expect(try deStore.refreshToken() == "de-refresh")

        try ruStore.clearRefreshToken()
        #expect(try ruStore.refreshToken() == nil)
        #expect(try deStore.refreshToken() == "de-refresh")
    }

    private func makeResolver(countryCode: String?) -> BackendStartupResolver {
        BackendStartupResolver(
            endpoints: BackendEndpoints(
                ru: BackendEndpoint(region: .ru, baseURL: ruURL),
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
