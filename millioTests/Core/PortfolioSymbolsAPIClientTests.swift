import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct PortfolioSymbolsAPIClientTests {
    @Test("Portfolio symbols sync uses PUT bearer request with sanitized payload")
    func testSyncSymbolsUsesPutAuthorizationAndBody() async throws {
        let session = StubHTTPSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 204,
                httpVersion: nil,
                headerFields: ["x-request-id": "portfolio-sync-1"]
            )!

            return (response, Data())
        }

        let client = makeClient(session: session)
        try await client.syncSymbols(["SPY", "BTC/USD"])
        let request = try #require(await session.lastRequest())

        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.url?.absoluteString == "https://example.com/api/v1/portfolio/symbols")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let payload = try JSONDecoder().decode(RecordedPortfolioSymbolsRequest.self, from: body)
        #expect(payload.symbols == ["SPY", "BTC/USD"])
    }

    @Test("401 response retries with refreshed access token")
    func testSyncSymbolsRetriesAfterUnauthorized() async throws {
        let statusCodes = ResponseSequence(values: [401, 204])
        let session = StubHTTPSession { request in
            let statusCode = statusCodes.next()
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["x-request-id": "portfolio-sync-\(statusCode)"]
            )!

            return (response, Data(#"{"message":"expired"}"#.utf8))
        }

        let authService = RefreshingStubAuthService()
        let client = PortfolioSymbolsAPIClient(
            authService: authService,
            configurationProvider: { AuthConfiguration(baseURL: URL(string: "https://example.com/api/v1")!) },
            session: session
        )

        try await client.syncSymbols(["SPY"])

        #expect(await authService.recordedForceRefreshCalls() == [false, true])
        #expect(await session.allRequests().count == 2)
        #expect(await session.allRequests().last?.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token")
    }

    private func makeClient(session: any HTTPSessionProtocol) -> PortfolioSymbolsAPIClient {
        PortfolioSymbolsAPIClient(
            authService: StubAuthService(),
            configurationProvider: { AuthConfiguration(baseURL: URL(string: "https://example.com/api/v1")!) },
            session: session
        )
    }
}

private actor RefreshingStubAuthService: AuthServiceProtocol {
    private var forceRefreshCalls: [Bool] = []

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        throw AuthServiceError.unconfigured
    }

    func restoreSession() async throws -> AuthSession? { nil }
    func lastKnownSession() async -> AuthSession? { nil }
    func currentUser() async throws -> AuthUser { throw AuthServiceError.unconfigured }
    func logout() async {}
    func accessTokenExpiryDate() async -> Date? { nil }

    func accessToken(forceRefresh: Bool) async throws -> String {
        forceRefreshCalls.append(forceRefresh)
        return forceRefresh ? "refreshed-token" : "access-token"
    }

    func recordedForceRefreshCalls() -> [Bool] {
        forceRefreshCalls
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

private final class ResponseSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int]

    init(values: [Int]) {
        self.values = values
    }

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

private struct RecordedPortfolioSymbolsRequest: Decodable {
    let symbols: [String]
}

private actor StubHTTPSession: HTTPSessionProtocol {
    private let handler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private var requests: [URLRequest] = []

    init(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let (response, data) = try handler(request)
        return (data, response)
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }

    func allRequests() -> [URLRequest] {
        requests
    }
}
