import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct AuthAPIClientTests {
    @Test("apple sign-in request adds diagnostic headers and sanitized token logs")
    func testAppleSignInAddsHeadersAndSanitizedLogs() async throws {
        let diagnostics = RecordingAuthDiagnostics()
        let expectation = RequestExpectation()
        URLProtocolStub.setHandler { request in
            expectation.capture(request)

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "backend-auth-1"]
            )!

            let data = Data(
                """
                {
                  "accessToken": "access-12345",
                  "refreshToken": "refresh-67890",
                  "accessTokenExpiresInSeconds": 900,
                  "user": {
                    "id": "user-1",
                    "email": "sid@example.com",
                    "emailVerified": true,
                    "firstName": "Sid",
                    "lastName": "Orkin",
                    "fullName": "Sid Orkin",
                    "avatarUrl": null,
                    "lastLoginAt": null
                  }
                }
                """.utf8
            )

            return (response, data)
        }
        defer { URLProtocolStub.reset() }

        let client = makeClient(diagnostics: diagnostics)

        _ = try await client.signInWithApple(
            request: AppleAuthRequest(
                identityToken: "raw-identity-token",
                email: "sid@example.com",
                firstName: "Sid",
                lastName: "Orkin"
            )
        )

        let request = try #require(expectation.snapshot())
        #expect(request.value(forHTTPHeaderField: "x-platform") == "ios")
        #expect(request.value(forHTTPHeaderField: "x-app-version") == "1.2.3(45)")
        #expect(UUID(uuidString: try #require(request.value(forHTTPHeaderField: "x-request-id"))) != nil)

        let records = diagnostics.snapshot()
        let started = try #require(records.first(where: { $0.phase == "auth.request.started" }))
        #expect(started.details["identityTokenPresent"] == "true")
        #expect(started.details["identityTokenLength"] == "18")
        #expect(started.details.values.contains("raw-identity-token") == false)

        let tokens = try #require(records.first(where: { $0.phase == "auth.tokens.received" }))
        #expect(tokens.backendRequestId == "backend-auth-1")
        #expect(tokens.details["accessTokenPresent"] == "true")
        #expect(tokens.details["refreshTokenPresent"] == "true")
        #expect(tokens.details.values.contains("access-12345") == false)
        #expect(tokens.details.values.contains("refresh-67890") == false)
    }

    @Test("429 response maps to rate limited auth error")
    func testRateLimitedResponseMapping() async {
        URLProtocolStub.setHandler { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["x-request-id": "backend-429"]
            )!
            let data = Data(#"{"message":"Too many attempts"}"#.utf8)
            return (response, data)
        }
        defer { URLProtocolStub.reset() }

        let client = makeClient()

        await #expect(throws: AuthServiceError.rateLimited(requestId: "backend-429", message: "Too many attempts")) {
            _ = try await client.refresh(refreshToken: "refresh-token")
        }
    }

    @Test("offline transport error maps to no internet category")
    func testTransportMapping() async {
        URLProtocolStub.setHandler { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { URLProtocolStub.reset() }

        let client = makeClient()

        await #expect(throws: AuthServiceError.transport(.noInternet)) {
            _ = try await client.refresh(refreshToken: "refresh-token")
        }
    }

    @Test("invalid response body maps to decoding error with backend request id")
    func testDecodingFailureKeepsBackendRequestId() async {
        URLProtocolStub.setHandler { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "backend-decode"]
            )!
            return (response, Data(#"{"unexpected":true}"#.utf8))
        }
        defer { URLProtocolStub.reset() }

        let client = makeClient()

        await #expect(throws: AuthServiceError.decodingFailed(requestId: "backend-decode")) {
            _ = try await client.refresh(refreshToken: "refresh-token")
        }
    }

    private func makeClient(diagnostics: any AuthDiagnosticsLogging = RecordingAuthDiagnostics()) -> AuthAPIClient {
        AuthAPIClient(
            configuration: AuthConfiguration(baseURL: URL(string: "https://example.com/api/v1")!),
            session: makeSession(),
            clientMetadata: AuthClientMetadata(platform: "ios", appVersion: "1.2.3(45)"),
            diagnostics: diagnostics
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
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

private final class RecordingAuthDiagnostics: AuthDiagnosticsLogging, @unchecked Sendable {
    struct Record: Sendable {
        let phase: String
        let operation: AuthRequestOperation?
        let requestId: String?
        let backendRequestId: String?
        let details: [String: String]
    }

    private let lock = NSLock()
    private var records: [Record] = []

    func log(
        _ level: LogLevel,
        phase: String,
        operation: AuthRequestOperation?,
        requestId: String?,
        backendRequestId: String?,
        details: [String: String]
    ) {
        lock.lock()
        records.append(
            Record(
                phase: phase,
                operation: operation,
                requestId: requestId,
                backendRequestId: backendRequestId,
                details: details
            )
        )
        lock.unlock()
    }

    func snapshot() -> [Record] {
        lock.lock()
        defer { lock.unlock() }
        return records
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
