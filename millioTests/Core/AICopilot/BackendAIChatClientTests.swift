import Foundation
import XCTest
@testable import millio

/// Транспорт чата: SSE через `URLSession.bytes`, фолбэк на JSON, повтор при 401, обрыв без финала.
final class BackendAIChatClientTests: XCTestCase {
    override func tearDown() {
        AIChatURLProtocolStub.reset()
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIChatURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeClient(auth: any AuthServiceProtocol = AIChatStubAuthService()) -> BackendAIChatClient {
        BackendAIChatClient(
            authService: auth,
            configurationProvider: { AuthConfiguration(baseURL: URL(string: "https://example.test/api/v1")!) },
            session: makeSession()
        )
    }

    private func request() -> AIChatRequest {
        AIChatRequest(
            schemaVersion: "1",
            locale: "ru",
            question: "Вопрос",
            history: nil,
            context: AIChatRequest.Context(
                period: AIPeriodSummaryRequest.Period(kind: "month", start: "2026-09-01", end: "2026-09-10"),
                currency: "RUB",
                totals: AIPeriodSummaryRequest.Totals(income: 1, expense: 1, net: 0, balanceEnd: 0),
                byCategory: []
            )
        )
    }

    private static func response(_ url: URL, status: Int, contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
    }

    private func collect(_ client: BackendAIChatClient) async -> (events: [AIChatEvent], error: Error?) {
        var events: [AIChatEvent] = []
        do {
            for try await event in client.stream(request()) { events.append(event) }
            return (events, nil)
        } catch {
            return (events, error)
        }
    }

    // MARK: - SSE

    func testStreamsDeltasThenDoneWithEventStreamAccept() async {
        let captured = AIChatCapturedRequests()
        AIChatURLProtocolStub.setHandler { request in
            captured.append(request)
            let body = """
            event: delta\r
            data: {"text":"Прив"}\r
            \r
            event: delta\r
            data: {"text":"ет"}\r
            \r
            event: done\r
            data: {"reply":"Привет","status":"ok"}\r
            \r

            """
            return (Self.response(request.url!, status: 200, contentType: "text/event-stream; charset=utf-8"), Data(body.utf8))
        }

        let result = await collect(makeClient())

        XCTAssertNil(result.error)
        XCTAssertEqual(result.events, [.delta("Прив"), .delta("ет"), .done(AIChatReply(reply: "Привет", status: .ok))])

        let sent = captured.first
        XCTAssertEqual(sent?.httpMethod, "POST")
        XCTAssertEqual(sent?.url?.path, "/api/v1/ai/chat")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    /// Регрессия: `bytes.lines` проглатывала пустые строки-разделители, кадры слипались в один,
    /// и финал не разбирался — каждый ответ выглядел как сбой, а печать по токенам пропадала.
    func testPlainLFFramesAreDeliveredOneByOne() async {
        AIChatURLProtocolStub.setHandler { request in
            let body = "event: delta\ndata: {\"text\":\"a\"}\n\n"
                + "event: delta\ndata: {\"text\":\"b\"}\n\n"
                + "event: done\ndata: {\"reply\":\"ab\",\"status\":\"ok\"}\n\n"
            return (Self.response(request.url!, status: 200, contentType: "text/event-stream"), Data(body.utf8))
        }

        let result = await collect(makeClient())

        XCTAssertNil(result.error)
        XCTAssertEqual(result.events, [.delta("a"), .delta("b"), .done(AIChatReply(reply: "ab", status: .ok))])
    }

    func testJSONResponseFromProxyIsStillDelivered() async {
        AIChatURLProtocolStub.setHandler { request in
            (Self.response(request.url!, status: 200, contentType: "application/json"),
             Data(#"{"reply":"Готово","status":"ok"}"#.utf8))
        }

        let result = await collect(makeClient())

        XCTAssertNil(result.error)
        XCTAssertEqual(result.events, [.done(AIChatReply(reply: "Готово", status: .ok))])
    }

    func testStreamWithoutDoneThrowsTransport() async {
        AIChatURLProtocolStub.setHandler { request in
            (Self.response(request.url!, status: 200, contentType: "text/event-stream"),
             Data("event: delta\ndata: {\"text\":\"Обор\"}\n\n".utf8))
        }

        let result = await collect(makeClient())

        XCTAssertEqual(result.events, [.delta("Обор")])
        XCTAssertEqual(result.error as? AIChatClientError, .transport)
    }

    // MARK: - Статусы

    func testRetriesOnceWithFreshTokenOn401() async {
        let auth = AIChatRefreshingAuthService()
        let counter = AIChatCallCounter()
        AIChatURLProtocolStub.setHandler { request in
            if counter.next() == 1 {
                return (Self.response(request.url!, status: 401, contentType: "application/json"), Data())
            }
            return (Self.response(request.url!, status: 200, contentType: "text/event-stream"),
                    Data("event: done\ndata: {\"reply\":\"ok\",\"status\":\"ok\"}\n\n".utf8))
        }

        let result = await collect(makeClient(auth: auth))
        let calls = await auth.recorded()

        XCTAssertNil(result.error)
        XCTAssertEqual(result.events, [.done(AIChatReply(reply: "ok", status: .ok))])
        XCTAssertEqual(calls, [false, true])
    }

    func testRateLimitIsReported() async {
        AIChatURLProtocolStub.setHandler { request in
            (Self.response(request.url!, status: 429, contentType: "application/json"), Data())
        }
        let result = await collect(makeClient())
        XCTAssertEqual(result.error as? AIChatClientError, .rateLimited)
    }

    func testValidationErrorIsReportedAsContractBreak() async {
        AIChatURLProtocolStub.setHandler { request in
            (Self.response(request.url!, status: 400, contentType: "application/json"), Data())
        }
        let result = await collect(makeClient())
        XCTAssertEqual(result.error as? AIChatClientError, .invalidContract)
    }

    func testNetworkFailureIsReportedAsTransport() async {
        AIChatURLProtocolStub.setHandler { _ in throw URLError(.notConnectedToInternet) }
        let result = await collect(makeClient())
        XCTAssertEqual(result.error as? AIChatClientError, .transport)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testUnavailableStubFinishesImmediatelyWithUnavailableStatus() async throws {
        var events: [AIChatEvent] = []
        for try await event in UnavailableAIChatClient().stream(request()) { events.append(event) }
        XCTAssertEqual(events, [.done(AIChatReply(reply: nil, status: .unavailable))])
    }
}

// MARK: - Test doubles

private final class AIChatURLProtocolStub: URLProtocol, @unchecked Sendable {
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

private final class AIChatCapturedRequests: @unchecked Sendable {
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

private final class AIChatCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private struct AIChatStubAuthService: AuthServiceProtocol {
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

private actor AIChatRefreshingAuthService: AuthServiceProtocol {
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
