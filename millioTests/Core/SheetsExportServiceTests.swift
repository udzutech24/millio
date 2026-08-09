import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct SheetsExportServiceTests {

    // MARK: - connectAccount

    @Test("connectAccount выполняет GET /sheets/auth-url с Bearer-токеном и возвращает URL")
    func testConnectAccountFetchesAuthURL() async throws {
        let session = SheetsStubHTTPSession { _ in
            let body = Data(#"{"url":"https://accounts.google.com/o/oauth2/auth?scope=spreadsheets"}"#.utf8)
            return (makeHTTP(url: "https://api.test/api/v1/sheets/auth-url", status: 200), body)
        }
        let service = makeService(session: session)
        let url = try await service.connectAccount()

        let request = try #require(await session.lastRequest())
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path.hasSuffix("/sheets/auth-url") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(url.absoluteString == "https://accounts.google.com/o/oauth2/auth?scope=spreadsheets")
    }

    // MARK: - handleOAuthCallback

    @Test("handleOAuthCallback выполняет POST /sheets/callback с кодом и устанавливает isConnected")
    func testHandleOAuthCallbackPostsCode() async throws {
        let session = SheetsStubHTTPSession { _ in
            return (makeHTTP(url: "https://api.test/api/v1/sheets/callback", status: 200), Data())
        }
        let defaults = UserDefaults(suiteName: "test.sheets.callback.\(UUID().uuidString)")!
        let service = makeService(session: session, defaults: defaults)

        try await service.handleOAuthCallback(code: "oauth-code-123")

        let request = try #require(await session.lastRequest())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path.hasSuffix("/sheets/callback") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        let body = try #require(request.httpBody)
        let payload = try JSONDecoder().decode([String: String].self, from: body)
        #expect(payload["code"] == "oauth-code-123")
        // Флаг isConnected должен быть выставлен локально сразу после успеха
        #expect(defaults.bool(forKey: SheetsExportDefaults.isConnected) == true)
    }

    @Test("handleOAuthCallback повторяет запрос с refreshed-токеном при 401")
    func testHandleOAuthCallbackRetriesOn401() async throws {
        let statuses = SheetsResponseSequence(values: [401, 200])
        let session = SheetsStubHTTPSession { request in
            let status = statuses.next()
            return (makeHTTP(url: try #require(request.url?.absoluteString), status: status), Data())
        }
        let authService = SheetsRefreshingStubAuthService()
        let service = makeSheetsService(authService: authService, session: session)

        try await service.handleOAuthCallback(code: "code-retry")

        #expect(await authService.recordedForceRefreshCalls() == [false, true])
        #expect(await session.allRequests().count == 2)
        #expect(
            await session.allRequests().last?.value(forHTTPHeaderField: "Authorization")
            == "Bearer refreshed-token"
        )
    }

    // MARK: - disconnectAccount

    @Test("disconnectAccount выполняет DELETE /sheets/disconnect и очищает defaults")
    func testDisconnectAccountDeletesAndClearsDefaults() async throws {
        let defaults = UserDefaults(suiteName: "test.sheets.disconnect.\(UUID().uuidString)")!
        defaults.set(true, forKey: SheetsExportDefaults.isConnected)
        defaults.set("sheet-id-abc", forKey: SheetsExportDefaults.spreadsheetId)

        let session = SheetsStubHTTPSession { _ in
            return (makeHTTP(url: "https://api.test/api/v1/sheets/disconnect", status: 200), Data())
        }
        let service = makeService(session: session, defaults: defaults)

        try await service.disconnectAccount()

        let request = try #require(await session.lastRequest())
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path.hasSuffix("/sheets/disconnect") == true)
        #expect(defaults.bool(forKey: SheetsExportDefaults.isConnected) == false)
        #expect(defaults.string(forKey: SheetsExportDefaults.spreadsheetId) == nil)
    }

    // MARK: - syncNow

    @Test("syncNow выполняет POST /sheets/sync с body и возвращает SheetsExportStatus")
    func testSyncNowPostsAndReturnsStatus() async throws {
        // Backend использует "connected" и "spreadsheetUrl" (не Swift-имена)
        let responseBody = """
        {
          "connected": true,
          "spreadsheetId": "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms",
          "spreadsheetUrl": "https://docs.google.com/spreadsheets/d/1Bxi",
          "lastSyncAt": "2026-06-02T10:00:00Z",
          "totalRows": 145
        }
        """.data(using: .utf8)!

        let session = SheetsStubHTTPSession { _ in
            return (makeHTTP(url: "https://api.test/api/v1/sheets/sync", status: 200), responseBody)
        }
        let service = makeService(session: session)
        let exportData = MillioExportData(
            transactions: [], accounts: [], archivedAccounts: [], budgets: [], investments: []
        )
        let status = try await service.syncNow(with: exportData)

        let request = try #require(await session.lastRequest())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path.hasSuffix("/sheets/sync") == true)
        // Body должен быть не nil — отправляем данные
        #expect(request.httpBody != nil)
        #expect(status.isConnected == true)
        #expect(status.totalRows == 145)
        #expect(status.syncState == .idle)
        #expect(status.spreadsheetId == "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
    }

    // MARK: - JSON-контракт (CodingKeys)

    @Test("SheetsExportStatus декодируется из backend JSON с ключами connected/spreadsheetUrl")
    func testStatusDecodesBackendJSON() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Backend никогда не шлёт syncState — должен дефолтиться в idle
        let json = Data("""
        {
          "connected": true,
          "spreadsheetId": "sheet-abc",
          "spreadsheetUrl": "https://docs.google.com/spreadsheets/d/sheet-abc",
          "lastSyncAt": "2026-06-02T09:00:00Z",
          "totalRows": 42
        }
        """.utf8)
        let status = try decoder.decode(SheetsExportStatus.self, from: json)
        #expect(status.isConnected == true)
        #expect(status.spreadsheetId == "sheet-abc")
        #expect(status.spreadsheetURL == URL(string: "https://docs.google.com/spreadsheets/d/sheet-abc"))
        #expect(status.totalRows == 42)
        #expect(status.syncState == .idle)
    }

    @Test("SheetsExportStatus.disconnected имеет корректные дефолтные значения")
    func testDisconnectedDefault() {
        let s = SheetsExportStatus.disconnected
        #expect(s.isConnected == false)
        #expect(s.spreadsheetId == nil)
        #expect(s.totalRows == 0)
        #expect(s.syncState == .idle)
    }

    // MARK: - getStatus (offline fallback)

    @Test("getStatus возвращает кэшированный статус при сетевой ошибке")
    func testGetStatusReturnsCachedOnNetworkError() async throws {
        let defaults = UserDefaults(suiteName: "test.sheets.status.\(UUID().uuidString)")!
        defaults.set(true, forKey: SheetsExportDefaults.isConnected)
        defaults.set("cached-sheet-id", forKey: SheetsExportDefaults.spreadsheetId)
        defaults.set(99, forKey: SheetsExportDefaults.totalRows)

        let session = SheetsStubHTTPSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = makeService(session: session, defaults: defaults)
        let status = await service.getStatus()

        #expect(status.isConnected == true)
        #expect(status.spreadsheetId == "cached-sheet-id")
        #expect(status.totalRows == 99)
    }

    @Test("getStatus возвращает disconnected при пустом кэше и сетевой ошибке")
    func testGetStatusReturnsDisconnectedWhenNoCacheAndNetworkFails() async throws {
        let defaults = UserDefaults(suiteName: "test.sheets.empty.\(UUID().uuidString)")!
        let session = SheetsStubHTTPSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = makeService(session: session, defaults: defaults)
        let status = await service.getStatus()

        #expect(status.isConnected == false)
        #expect(status == .disconnected)
    }

    // MARK: - Обработка ошибок

    @Test("validateResponse бросает tokenRevoked при 403")
    func testValidateResponseThrowsTokenRevokedOn403() async throws {
        let session = SheetsStubHTTPSession { _ in
            return (makeHTTP(url: "https://api.test/api/v1/sheets/sync", status: 403), Data())
        }
        let service = makeService(session: session)

        let emptyExport = MillioExportData(
            transactions: [], accounts: [], archivedAccounts: [], budgets: [], investments: []
        )
        await #expect(throws: SheetsExportError.tokenRevoked) {
            _ = try await service.syncNow(with: emptyExport)
        }
    }

    @Test("validateResponse бросает backend с сообщением при 500")
    func testValidateResponseThrowsBackendErrorOn500() async throws {
        let body = Data(#"{"message":"Internal Server Error"}"#.utf8)
        let session = SheetsStubHTTPSession { _ in
            return (makeHTTP(url: "https://api.test/api/v1/sheets/sync", status: 500), body)
        }
        let service = makeService(session: session)
        let emptyExport = MillioExportData(
            transactions: [], accounts: [], archivedAccounts: [], budgets: [], investments: []
        )
        do {
            _ = try await service.syncNow(with: emptyExport)
            Issue.record("Должен бросить ошибку")
        } catch SheetsExportError.backend(let statusCode, let message) {
            #expect(statusCode == 500)
            #expect(message == "Internal Server Error")
        }
    }

    // MARK: - Фабрики

    private func makeService(
        session: SheetsStubHTTPSession,
        defaults: UserDefaults = .standard
    ) -> SheetsExportServiceImpl {
        SheetsExportServiceImpl(
            authService: SheetsStubAuthService(),
            configurationProvider: { AuthConfiguration(baseURL: URL(string: "https://api.test/api/v1")!) },
            session: session,
            defaults: defaults
        )
    }

    private func makeSheetsService(
        authService: any AuthServiceProtocol,
        session: SheetsStubHTTPSession
    ) -> SheetsExportServiceImpl {
        SheetsExportServiceImpl(
            authService: authService,
            configurationProvider: { AuthConfiguration(baseURL: URL(string: "https://api.test/api/v1")!) },
            session: session
        )
    }
}

// MARK: - SheetsExportTrigger tests

@Suite(.serialized)
struct SheetsExportTriggerTests {

    @Test("notifyTransactionAdded запускает sync после дебаунса")
    func testNotifyTriggersSync() async throws {
        let syncCalled = SheetsCallCounter()
        // connected: true — иначе guard в триггере заблокирует sync
        let exportService = SheetsSpyExportService(onSync: { await syncCalled.increment() }, connected: true)
        let trigger = SheetsExportTrigger(exportService: exportService, isEnabled: { true })
        let emptyExport = MillioExportData(
            transactions: [], accounts: [], archivedAccounts: [], budgets: [], investments: []
        )

        // Шлём три вызова подряд — должен сработать только один sync
        await trigger.notifyTransactionAdded(with: emptyExport)
        await trigger.notifyTransactionAdded(with: emptyExport)
        await trigger.notifyTransactionAdded(with: emptyExport)

        // Ждём дебаунс (5с) + небольшой запас
        try await Task.sleep(for: .seconds(6))

        #expect(await syncCalled.count == 1)
    }

    @Test("notifyTransactionAdded не запускает sync когда аккаунт не подключён")
    func testNotifySkipsSyncWhenDisconnected() async throws {
        let syncCalled = SheetsCallCounter()
        // connected: false — guard в триггере должен заблокировать sync
        let exportService = SheetsSpyExportService(onSync: { await syncCalled.increment() }, connected: false)
        let trigger = SheetsExportTrigger(exportService: exportService, isEnabled: { true })
        let emptyExport = MillioExportData(
            transactions: [], accounts: [], archivedAccounts: [], budgets: [], investments: []
        )

        await trigger.notifyTransactionAdded(with: emptyExport)
        try await Task.sleep(for: .seconds(6))

        #expect(await syncCalled.count == 0)
    }

    @Test("Google Sheets kill switch не запрашивает status и не запускает sync")
    func testDisabledKillSwitchSkipsAllWork() async {
        let syncCalled = SheetsCallCounter()
        let exportService = SheetsSpyExportService(
            onSync: { await syncCalled.increment() },
            connected: true
        )
        let trigger = SheetsExportTrigger(exportService: exportService, isEnabled: { false })
        let emptyExport = MillioExportData(
            transactions: [], accounts: [], archivedAccounts: [], budgets: [], investments: []
        )

        await trigger.syncImmediately(with: emptyExport)
        await trigger.notifyTransactionAdded(with: emptyExport)

        #expect(await syncCalled.count == 0)
        #expect(await exportService.statusCallCount == 0)
    }
}

// MARK: - Вспомогательные типы

private func makeHTTP(url: String, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
}

private actor SheetsStubHTTPSession: HTTPSessionProtocol {
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

    func lastRequest() -> URLRequest? { requests.last }
    func allRequests() -> [URLRequest] { requests }
}

private struct SheetsStubAuthService: AuthServiceProtocol {
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

private actor SheetsRefreshingStubAuthService: AuthServiceProtocol {
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

    func recordedForceRefreshCalls() -> [Bool] { calls }
}

private final class SheetsResponseSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int]
    init(values: [Int]) { self.values = values }
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        return values.removeFirst()
    }
}

private actor SheetsSpyExportService: SheetsExportServiceProtocol {
    private let onSync: @Sendable () async -> Void
    // Триггер проверяет isConnected перед запуском — возвращаем connected чтобы sync дошёл
    private let connectedStatus: SheetsExportStatus
    private(set) var statusCallCount = 0

    init(
        onSync: @escaping @Sendable () async -> Void,
        connected: Bool = true
    ) {
        self.onSync = onSync
        self.connectedStatus = connected
            ? SheetsExportStatus(
                isConnected: true,
                spreadsheetId: "spy-sheet",
                spreadsheetURL: nil,
                lastSyncAt: nil,
                totalRows: 0,
                syncState: .idle
              )
            : .disconnected
    }

    func connectAccount() async throws -> URL { URL(string: "https://example.com")! }
    func handleOAuthCallback(code: String) async throws {}
    func disconnectAccount() async throws {}
    func getStatus() async -> SheetsExportStatus {
        statusCallCount += 1
        return connectedStatus
    }

    func syncNow(with data: MillioExportData) async throws -> SheetsExportStatus {
        await onSync()
        return connectedStatus
    }
}

private actor SheetsCallCounter {
    var count: Int = 0
    func increment() { count += 1 }
}
