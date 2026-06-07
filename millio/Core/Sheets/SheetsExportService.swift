import Foundation

// MARK: - Ошибки экспорта

enum SheetsExportError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case unauthorized
    case backend(statusCode: Int, message: String)
    case transport(String)
    // Токен отозван пользователем в Google Account — требует повторного подключения
    case tokenRevoked

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Некорректная конфигурация бэкенда для Google Sheets."
        case .unauthorized:
            return "Сессия истекла. Войдите снова."
        case .backend(_, let message):
            return message
        case .transport(let detail):
            return detail
        case .tokenRevoked:
            return "Доступ к Google аккаунту отозван. Подключитесь снова."
        }
    }
}

// MARK: - Статус экспорта

struct SheetsExportStatus: Codable, Sendable, Equatable {
    let isConnected: Bool
    let spreadsheetId: String?
    let spreadsheetURL: URL?
    let lastSyncAt: Date?
    let totalRows: Int
    let syncState: SyncState

    enum SyncState: String, Codable, Sendable {
        case idle
        case syncing
        case error
    }

    // Backend шлёт "connected", "spreadsheetUrl" — маппим на Swift-имена
    enum CodingKeys: String, CodingKey {
        case isConnected = "connected"
        case spreadsheetId
        case spreadsheetURL = "spreadsheetUrl"
        case lastSyncAt
        case totalRows
        case syncState
    }

    // Дефолтное значение syncState — backend его не шлёт в /status
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isConnected = try c.decode(Bool.self, forKey: .isConnected)
        spreadsheetId = try c.decodeIfPresent(String.self, forKey: .spreadsheetId)
        let urlString = try c.decodeIfPresent(String.self, forKey: .spreadsheetURL)
        spreadsheetURL = urlString.flatMap { URL(string: $0) }
        lastSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        totalRows = try c.decodeIfPresent(Int.self, forKey: .totalRows) ?? 0
        syncState = try c.decodeIfPresent(SyncState.self, forKey: .syncState) ?? .idle
    }

    init(
        isConnected: Bool,
        spreadsheetId: String?,
        spreadsheetURL: URL?,
        lastSyncAt: Date?,
        totalRows: Int,
        syncState: SyncState
    ) {
        self.isConnected = isConnected
        self.spreadsheetId = spreadsheetId
        self.spreadsheetURL = spreadsheetURL
        self.lastSyncAt = lastSyncAt
        self.totalRows = totalRows
        self.syncState = syncState
    }

    static let disconnected = SheetsExportStatus(
        isConnected: false,
        spreadsheetId: nil,
        spreadsheetURL: nil,
        lastSyncAt: nil,
        totalRows: 0,
        syncState: .idle
    )
}

// MARK: - Протокол

protocol SheetsExportServiceProtocol: Sendable {
    /// Возвращает URL для открытия в Safari (OAuth Google)
    func connectAccount() async throws -> URL
    /// Вызывается после redirect с OAuth-кодом
    func handleOAuthCallback(code: String) async throws
    func disconnectAccount() async throws
    /// Полная синхронизация — отправляет снимок данных на backend
    func syncNow(with data: MillioExportData) async throws -> SheetsExportStatus
    func getStatus() async -> SheetsExportStatus
}

// MARK: - UserDefaults ключи

enum SheetsExportDefaults {
    private static let prefix = "millio.sheets."
    static let isConnected = prefix + "isConnected"
    static let spreadsheetId = prefix + "spreadsheetId"
    static let spreadsheetURL = prefix + "spreadsheetURL"
    static let lastSyncAt = prefix + "lastSyncAt"
    static let totalRows = prefix + "totalRows"
}

// MARK: - Реализация

/// Сервис одностороннего экспорта данных Millio в Google Sheets через бэкенд.
/// iOS не обращается к Google API напрямую — вся OAuth-логика на NestJS.
actor SheetsExportServiceImpl: SheetsExportServiceProtocol {

    private let authService: any AuthServiceProtocol
    private let configurationProvider: @Sendable () throws -> AuthConfiguration
    private let session: any HTTPSessionProtocol
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration,
        session: any HTTPSessionProtocol = URLSession.shared,
        defaults: UserDefaults = .standard
    ) {
        self.authService = authService
        self.configurationProvider = configurationProvider
        self.session = session
        self.defaults = defaults

        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    // MARK: - Подключение

    func connectAccount() async throws -> URL {
        let accessToken = try await authService.accessToken(forceRefresh: false)
        return try await fetchAuthURL(accessToken: accessToken)
    }

    func handleOAuthCallback(code: String) async throws {
        do {
            let accessToken = try await authService.accessToken(forceRefresh: false)
            try await postCallback(code: code, accessToken: accessToken)
        } catch SheetsExportError.unauthorized {
            let refreshed = try await authService.accessToken(forceRefresh: true)
            try await postCallback(code: code, accessToken: refreshed)
        }
        // Подключение прошло — обновляем локальный флаг сразу
        defaults.set(true, forKey: SheetsExportDefaults.isConnected)
    }

    func disconnectAccount() async throws {
        do {
            let accessToken = try await authService.accessToken(forceRefresh: false)
            try await deleteDisconnect(accessToken: accessToken)
        } catch SheetsExportError.unauthorized {
            let refreshed = try await authService.accessToken(forceRefresh: true)
            try await deleteDisconnect(accessToken: refreshed)
        }
        clearLocalState()
    }

    // MARK: - Синхронизация

    func syncNow(with data: MillioExportData) async throws -> SheetsExportStatus {
        do {
            let accessToken = try await authService.accessToken(forceRefresh: false)
            return try await postSync(data: data, accessToken: accessToken)
        } catch SheetsExportError.unauthorized {
            let refreshed = try await authService.accessToken(forceRefresh: true)
            return try await postSync(data: data, accessToken: refreshed)
        }
    }

    func getStatus() async -> SheetsExportStatus {
        do {
            let accessToken = try await authService.accessToken(forceRefresh: false)
            let status = try await fetchStatus(accessToken: accessToken)
            persistStatus(status)
            return status
        } catch {
            AppLogger.log(.warning, category: "SheetsExport", "getStatus failed: \(error.localizedDescription)")
            return cachedStatus()
        }
    }

    // MARK: - Сетевые методы

    private func fetchAuthURL(accessToken: String) async throws -> URL {
        let url = try baseURL().appending(path: "/sheets/auth-url")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        struct AuthURLResponse: Decodable { let url: String }
        let envelope = try decoder.decode(AuthURLResponse.self, from: data)
        guard let oauthURL = URL(string: envelope.url) else {
            throw SheetsExportError.backend(statusCode: 200, message: "Невалидный OAuth URL от бэкенда.")
        }
        return oauthURL
    }

    private func postCallback(code: String, accessToken: String) async throws {
        struct CallbackBody: Encodable { let code: String }
        let url = try baseURL().appending(path: "/sheets/callback")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(CallbackBody(code: code))

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
    }

    private func deleteDisconnect(accessToken: String) async throws {
        let url = try baseURL().appending(path: "/sheets/disconnect")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
    }

    private func postSync(data exportData: MillioExportData, accessToken: String) async throws -> SheetsExportStatus {
        let url = try baseURL().appending(path: "/sheets/sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(exportData)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let status = try decoder.decode(SheetsExportStatus.self, from: data)
        persistStatus(status)
        return status
    }

    private func fetchStatus(accessToken: String) async throws -> SheetsExportStatus {
        let url = try baseURL().appending(path: "/sheets/status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decoder.decode(SheetsExportStatus.self, from: data)
    }

    // MARK: - Вспомогательные методы

    private func baseURL() throws -> URL {
        #if targetEnvironment(simulator)
        // Симулятор → локальный dev-бэкенд. Продакшн: убрать когда sheets задеплоен на прод.
        return URL(string: "http://localhost:3000/api/v1")!
        #else
        do {
            return try configurationProvider().baseURL
        } catch {
            throw SheetsExportError.invalidConfiguration
        }
        #endif
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw SheetsExportError.transport(error.localizedDescription)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SheetsExportError.transport("Некорректный HTTP-ответ от сервера.")
        }

        struct ErrorEnvelope: Decodable {
            let message: String?
            let error: String?
            var resolved: String { message ?? error ?? "Ошибка сервера." }
        }

        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw SheetsExportError.unauthorized
        case 403:
            // 403 от /sheets означает отзыв токена Google
            throw SheetsExportError.tokenRevoked
        default:
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).resolved)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SheetsExportError.backend(statusCode: http.statusCode, message: msg)
        }
    }

    // MARK: - Локальный кэш статуса

    private func persistStatus(_ status: SheetsExportStatus) {
        defaults.set(status.isConnected, forKey: SheetsExportDefaults.isConnected)
        defaults.set(status.spreadsheetId, forKey: SheetsExportDefaults.spreadsheetId)
        defaults.set(status.spreadsheetURL?.absoluteString, forKey: SheetsExportDefaults.spreadsheetURL)
        defaults.set(status.lastSyncAt, forKey: SheetsExportDefaults.lastSyncAt)
        defaults.set(status.totalRows, forKey: SheetsExportDefaults.totalRows)
    }

    private func clearLocalState() {
        defaults.removeObject(forKey: SheetsExportDefaults.isConnected)
        defaults.removeObject(forKey: SheetsExportDefaults.spreadsheetId)
        defaults.removeObject(forKey: SheetsExportDefaults.spreadsheetURL)
        defaults.removeObject(forKey: SheetsExportDefaults.lastSyncAt)
        defaults.removeObject(forKey: SheetsExportDefaults.totalRows)
    }

    private func cachedStatus() -> SheetsExportStatus {
        let isConnected = defaults.bool(forKey: SheetsExportDefaults.isConnected)
        guard isConnected else { return .disconnected }

        let spreadsheetId = defaults.string(forKey: SheetsExportDefaults.spreadsheetId)
        let spreadsheetURLString = defaults.string(forKey: SheetsExportDefaults.spreadsheetURL)
        let spreadsheetURL = spreadsheetURLString.flatMap { URL(string: $0) }
        let lastSyncAt = defaults.object(forKey: SheetsExportDefaults.lastSyncAt) as? Date
        let totalRows = defaults.integer(forKey: SheetsExportDefaults.totalRows)

        return SheetsExportStatus(
            isConnected: true,
            spreadsheetId: spreadsheetId,
            spreadsheetURL: spreadsheetURL,
            lastSyncAt: lastSyncAt,
            totalRows: totalRows,
            syncState: .idle
        )
    }
}
