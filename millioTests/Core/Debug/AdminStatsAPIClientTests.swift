import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct AdminStatsAPIClientTests {
    @Test("Symbols request uses bearer token and limit query")
    func testFetchSymbolsAddsAuthorizationAndLimit() async throws {
        let expectation = RequestExpectation()
        URLProtocolStub.setHandler { request in
            expectation.capture(request)

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "admin-stats-1"]
            )!

            let data = Data(
                """
                {
                  "limit": 25,
                  "items": [
                    { "symbol": "AAPL", "usersCount": 18 }
                  ],
                  "generatedAt": "2026-03-27T12:00:00.000Z"
                }
                """.utf8
            )

            return (response, data)
        }
        defer { URLProtocolStub.reset() }

        let client = makeClient()
        let response = try await client.fetchSymbols(limit: 25)
        let request = try #require(expectation.snapshot())

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.url?.absoluteString == "https://example.com/api/v1/admin/stats/symbols?limit=25")
        #expect(response.items == [AdminStatsSymbolCount(symbol: "AAPL", usersCount: 18)])
    }

    @Test("403 response maps to forbidden admin stats error")
    func testForbiddenMapping() async {
        URLProtocolStub.setHandler { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 403,
                httpVersion: nil,
                headerFields: ["x-request-id": "admin-forbidden"]
            )!
            let data = Data(#"{"message":"ADMIN access required"}"#.utf8)
            return (response, data)
        }
        defer { URLProtocolStub.reset() }

        let client = makeClient()

        await #expect(throws: AdminStatsAPIClientError.forbidden(message: "ADMIN access required", requestId: "admin-forbidden")) {
            _ = try await client.fetchOverview()
        }
    }

    private func makeClient() -> AdminStatsAPIClient {
        AdminStatsAPIClient(
            authService: StubAuthService(),
            configurationProvider: { AuthConfiguration(baseURL: URL(string: "https://example.com/api/v1")!) },
            session: makeSession()
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private struct StubAuthService: AuthServiceProtocol {
    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        throw AuthServiceError.unconfigured
    }

    func restoreSession() async throws -> AuthSession? { nil }
    func lastKnownSession() async -> AuthSession? { nil }
    func currentUser() async throws -> AuthUser { throw AuthServiceError.unconfigured }
    func logout() async {}
    func accessTokenExpiryDate() async -> Date? { nil }
    func accessToken(forceRefresh: Bool) async throws -> String { "access-token" }
}

private final class RequestExpectation: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func capture(_ request: URLRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func snapshot() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
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
