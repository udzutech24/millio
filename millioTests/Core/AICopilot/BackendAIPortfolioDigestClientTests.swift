import Foundation
import XCTest
@testable import millio

/// Транспорт дайджеста: путь, Bearer, один повтор при 401 и маппинг HTTP-ошибок.
final class BackendAIPortfolioDigestClientTests: XCTestCase {
    override func tearDown() {
        PortfolioDigestURLProtocolStub.reset()
        super.tearDown()
    }

    private func makeClient(auth: any AuthServiceProtocol = PortfolioDigestStubAuthService()) -> BackendAIPortfolioDigestClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortfolioDigestURLProtocolStub.self]
        return BackendAIPortfolioDigestClient(
            authService: auth,
            configurationProvider: { AuthConfiguration(baseURL: URL(string: "https://example.test/api/v1")!) },
            session: URLSession(configuration: configuration)
        )
    }

    private func request() -> AIPortfolioDigestRequest {
        AIPortfolioDigestRequest(
            schemaVersion: "1",
            locale: "ru",
            currency: "RUB",
            window: "month",
            totals: AIPortfolioDigestRequest.Totals(value: 6_000, changeAmount: 800, changePercent: 15.38),
            positions: [
                AIPortfolioDigestRequest.Position(symbol: "SBER", assetClass: "stock", value: 3_000, sharePercent: 50, changePercent: 7.14)
            ]
        )
    }

    private static func http(_ url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    }

    private static let okBody = Data(#"{"headline":"Итог","notes":[],"disclaimer":"Информация, не инвестиционная рекомендация.","status":"ok"}"#.utf8)

    func testPostsToPortfolioDigestWithBearerAndDecodesResponse() async throws {
        let captured = PortfolioDigestCapturedRequests()
        PortfolioDigestURLProtocolStub.setHandler { request in
            captured.append(request)
            return (Self.http(request.url!, status: 200), Self.okBody)
        }

        let response = try await makeClient().digest(request())

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.text?.headline, "Итог")
        let sent = try XCTUnwrap(captured.first)
        XCTAssertEqual(sent.url?.path, "/api/v1/ai/portfolio-digest")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testRetriesOnceWithRefreshedTokenAfter401() async throws {
        let auth = PortfolioDigestRefreshingAuthService()
        PortfolioDigestURLProtocolStub.setHandler { request in
            let isRefreshed = request.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token"
            return (Self.http(request.url!, status: isRefreshed ? 200 : 401), isRefreshed ? Self.okBody : Data())
        }

        let response = try await makeClient(auth: auth).digest(request())

        XCTAssertEqual(response.status, .ok)
        let calls = await auth.recorded()
        XCTAssertEqual(calls, [false, true])
    }

    func testHttpFailuresMapToClientErrors() async {
        let cases: [(Int, AICopilotClientError)] = [(429, .rateLimited), (400, .invalidContract), (503, .unavailable)]
        for (status, expected) in cases {
            PortfolioDigestURLProtocolStub.setHandler { request in (Self.http(request.url!, status: status), Data()) }
            do {
                _ = try await makeClient().digest(request())
                XCTFail("HTTP \(status) должен бросить ошибку")
            } catch {
                XCTAssertEqual(error as? AICopilotClientError, expected, "HTTP \(status)")
            }
        }
    }

    func testNetworkFailureMapsToTransport() async {
        PortfolioDigestURLProtocolStub.setHandler { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeClient().digest(request())
            XCTFail("Офлайн должен бросить ошибку")
        } catch {
            XCTAssertEqual(error as? AICopilotClientError, .transport)
        }
    }

    func testUnavailableStubNeverTouchesNetwork() async {
        let client = UnavailableAIPortfolioDigestClient()
        XCTAssertFalse(client.isAvailable)
        do {
            _ = try await client.digest(request())
            XCTFail("Заглушка должна бросать ошибку")
        } catch {
            XCTAssertEqual(error as? AICopilotClientError, .unavailable)
        }
    }
}

// MARK: - Test doubles

private final class PortfolioDigestURLProtocolStub: URLProtocol, @unchecked Sendable {
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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

private final class PortfolioDigestCapturedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        values.append(request)
        lock.unlock()
    }

    var first: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return values.first
    }
}

private struct PortfolioDigestStubAuthService: AuthServiceProtocol {
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

private actor PortfolioDigestRefreshingAuthService: AuthServiceProtocol {
    private var calls: [Bool] = []

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        throw AuthServiceError.unconfigured
    }

    func restoreSession() async throws -> AuthSession? { nil }
    func lastKnownSession() async -> AuthSession? { nil }
    func currentUser() async throws -> AuthUser { throw AuthServiceError.unconfigured }
    func logout() async {}
    func accessTokenExpiryDate() async -> Date? { nil }

    func accessToken(forceRefresh: Bool) async throws -> String {
        calls.append(forceRefresh)
        return forceRefresh ? "refreshed-token" : "access-token"
    }

    func recorded() -> [Bool] { calls }
}
