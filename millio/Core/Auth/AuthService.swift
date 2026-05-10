@preconcurrency import AuthenticationServices
import Foundation
import Observation
import Security

enum AuthTransportError: LocalizedError, Equatable, Sendable {
    case noInternet
    case timeout
    case cancelled
    case tls
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noInternet:
            return "The Internet connection appears to be offline."
        case .timeout:
            return "The request timed out."
        case .cancelled:
            return "The request was cancelled."
        case .tls:
            return "A secure connection could not be established."
        case .network(let message):
            return message
        }
    }

    static func from(_ error: Error) -> AuthTransportError {
        if error is CancellationError {
            return .cancelled
        }

        guard let urlError = error as? URLError else {
            return .network(error.localizedDescription)
        }

        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed:
            return .noInternet
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .timeout
        case .cancelled:
            return .cancelled
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .tls
        default:
            return .network(urlError.localizedDescription)
        }
    }
}

enum AuthServiceError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case invalidIdentityToken
    case unexpectedAuthorizationCredential
    case notAuthenticated
    case unauthorized(requestId: String? = nil)
    case forbidden(requestId: String? = nil, message: String)
    case rateLimited(requestId: String? = nil, message: String, retryAfter: TimeInterval? = nil)
    case server(statusCode: Int, message: String, requestId: String? = nil)
    case backend(statusCode: Int, message: String, requestId: String? = nil)
    case transport(AuthTransportError)
    case invalidResponse(requestId: String? = nil)
    case decodingFailed(requestId: String? = nil)
    case tokenPersistenceFailed(String)
    case unconfigured

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Backend API base URL configuration is missing or invalid."
        case .invalidIdentityToken:
            return "Apple Sign In did not return a valid identity token."
        case .unexpectedAuthorizationCredential:
            return "Unexpected Apple authorization credential type."
        case .notAuthenticated:
            return "No active authenticated session."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .forbidden(_, let message),
             .rateLimited(_, let message, _),
             .server(_, let message, _),
             .backend(_, let message, _):
            return message
        case .transport(let transportError):
            return transportError.errorDescription
        case .invalidResponse:
            return "Invalid auth HTTP response."
        case .decodingFailed:
            return "Failed to decode backend auth response."
        case .tokenPersistenceFailed(let message):
            return message
        case .unconfigured:
            return "Auth service is not configured yet."
        }
    }

    var requestId: String? {
        switch self {
        case .unauthorized(let requestId),
             .forbidden(let requestId, _),
             .rateLimited(let requestId, _, _),
             .server(_, _, let requestId),
             .backend(_, _, let requestId),
             .invalidResponse(let requestId),
             .decodingFailed(let requestId):
            return requestId
        case .invalidConfiguration,
             .invalidIdentityToken,
             .unexpectedAuthorizationCredential,
             .notAuthenticated,
             .transport,
             .tokenPersistenceFailed,
             .unconfigured:
            return nil
        }
    }
}

enum AuthFlowError: LocalizedError, Equatable, Sendable {
    case postLoginBootstrapFailed(String)
    case wrongSessionNamespace

    var errorDescription: String? {
        switch self {
        case .postLoginBootstrapFailed(let reason):
            return reason
        case .wrongSessionNamespace:
            return "Session was created for a different backend or region."
        }
    }
}

protocol RefreshTokenStoreProtocol: Sendable {
    func refreshToken() throws -> String?
    func setRefreshToken(_ value: String) throws
    func clearRefreshToken() throws
}

protocol AuthSessionSnapshotStoreProtocol: Sendable {
    func session() throws -> AuthSession?
    func setSession(_ session: AuthSession) throws
    func clearSession() throws
}

// Stores only non-secret session metadata so the UI can survive transient restore failures.
private struct PersistedAuthSessionSnapshot: Codable, Sendable {
    let user: AuthUser
    let accessTokenExpiresAt: Date
    let savedAt: Date

    init(session: AuthSession, savedAt: Date = Date()) {
        self.user = session.user
        self.accessTokenExpiresAt = session.accessTokenExpiresAt
        self.savedAt = savedAt
    }

    func makeSession() -> AuthSession {
        AuthSession(
            user: user,
            accessTokenExpiresAt: accessTokenExpiresAt,
            metadata: AuthResponseMetadata(
                statusCode: 200,
                requestId: "local-session-snapshot",
                clientRequestId: "local-session-snapshot",
                durationMilliseconds: 0
            ),
            source: .cachedSnapshot
        )
    }
}

final class UserDefaultsAuthSessionSnapshotStore: AuthSessionSnapshotStoreProtocol, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        key: String = "auth.sessionSnapshot"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func session() throws -> AuthSession? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        do {
            let snapshot = try decoder.decode(PersistedAuthSessionSnapshot.self, from: data)
            return snapshot.makeSession()
        } catch {
            defaults.removeObject(forKey: key)
            throw AuthServiceError.tokenPersistenceFailed("Stored auth session snapshot is corrupted.")
        }
    }

    func setSession(_ session: AuthSession) throws {
        let data = try encoder.encode(PersistedAuthSessionSnapshot(session: session))
        defaults.set(data, forKey: key)
    }

    func clearSession() throws {
        defaults.removeObject(forKey: key)
    }
}

struct KeychainRefreshTokenStore: RefreshTokenStoreProtocol {
    private let service: String
    private let account: String
    private let accessible: String

    init(
        service: String = Bundle.main.bundleIdentifier.map { "\($0).auth" } ?? "millio.auth",
        account: String = "refreshToken",
        accessible: String = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    ) {
        self.service = service
        self.account = account
        self.accessible = accessible
    }

    func refreshToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw AuthServiceError.tokenPersistenceFailed("Refresh token is corrupted in Keychain.")
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw AuthServiceError.tokenPersistenceFailed("Keychain read failed with status \(status).")
        }
    }

    func setRefreshToken(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw AuthServiceError.tokenPersistenceFailed("Keychain update failed with status \(status).")
            }
            return
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = accessible
        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthServiceError.tokenPersistenceFailed("Keychain save failed with status \(status).")
        }
    }

    func clearRefreshToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthServiceError.tokenPersistenceFailed("Keychain delete failed with status \(status).")
        }
    }
}

actor AuthTokenStore {
    private struct AccessTokenState: Sendable {
        let value: String
        let expiresAt: Date
    }

    private let refreshTokenStore: any RefreshTokenStoreProtocol
    private let expirationLeeway: TimeInterval
    private var accessTokenState: AccessTokenState?

    init(
        refreshTokenStore: any RefreshTokenStoreProtocol = KeychainRefreshTokenStore(),
        expirationLeeway: TimeInterval = 30
    ) {
        self.refreshTokenStore = refreshTokenStore
        self.expirationLeeway = expirationLeeway
    }

    func store(
        _ response: AuthResponse,
        now: Date = Date(),
        metadata: AuthResponseMetadata,
        source: AuthSessionSource
    ) throws -> AuthSession {
        let expiresAt = now.addingTimeInterval(TimeInterval(response.accessTokenExpiresInSeconds))
        accessTokenState = AccessTokenState(value: response.accessToken, expiresAt: expiresAt)
        try refreshTokenStore.setRefreshToken(response.refreshToken)
        return AuthSession(
            user: response.user,
            accessTokenExpiresAt: expiresAt,
            metadata: metadata,
            source: source
        )
    }

    func accessToken() -> String? {
        guard let accessTokenState,
              accessTokenState.expiresAt.timeIntervalSinceNow > expirationLeeway else {
            accessTokenState = nil
            return nil
        }
        return accessTokenState.value
    }

    func accessTokenExpiresAt() -> Date? {
        accessTokenState?.expiresAt
    }

    func refreshToken() throws -> String? {
        try refreshTokenStore.refreshToken()
    }

    func clear() throws {
        accessTokenState = nil
        try refreshTokenStore.clearRefreshToken()
    }
}

private struct AuthRateLimitBackoffState: Sendable {
    private static let baseDelay: TimeInterval = 1
    private static let maxDelay: TimeInterval = 32

    private(set) var consecutiveFailures = 0
    private var nextAllowedAttemptAt: Date?
    private var lastMessage = "Too many attempts. Please wait a bit and try again."
    private var lastRequestId: String?

    mutating func failFastError(now: Date = Date()) -> AuthServiceError? {
        guard let nextAllowedAttemptAt else {
            return nil
        }

        let remainingDelay = nextAllowedAttemptAt.timeIntervalSince(now)
        guard remainingDelay > 0 else {
            self.nextAllowedAttemptAt = nil
            return nil
        }

        return .rateLimited(
            requestId: lastRequestId,
            message: lastMessage,
            retryAfter: remainingDelay
        )
    }

    mutating func registerRateLimit(
        requestId: String?,
        message: String,
        retryAfter: TimeInterval?,
        now: Date = Date()
    ) -> AuthServiceError {
        consecutiveFailures += 1

        let exponentialDelay = min(
            Self.baseDelay * pow(2, Double(max(consecutiveFailures - 1, 0))),
            Self.maxDelay
        )
        let resolvedDelay = max(retryAfter ?? 0, exponentialDelay)

        nextAllowedAttemptAt = now.addingTimeInterval(resolvedDelay)
        lastMessage = message
        lastRequestId = requestId

        return .rateLimited(
            requestId: requestId,
            message: message,
            retryAfter: resolvedDelay
        )
    }

    mutating func reset() {
        consecutiveFailures = 0
        nextAllowedAttemptAt = nil
        lastRequestId = nil
    }
}

protocol AuthAPIClientProtocol: Sendable {
    func signInWithApple(request: AppleAuthRequest) async throws -> AuthNetworkResult<AuthResponse>
    func refresh(refreshToken: String) async throws -> AuthNetworkResult<AuthResponse>
    func logout(refreshToken: String) async throws -> AuthNetworkResult<LogoutResponse>
    func me(accessToken: String) async throws -> AuthNetworkResult<AuthUser>
}

struct AuthAPIClient: AuthAPIClientProtocol {
    private struct ErrorEnvelope: Decodable {
        let message: MessageValue?
        let error: String?

        enum MessageValue: Decodable {
            case string(String)
            case array([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .string(value)
                    return
                }
                if let value = try? container.decode([String].self) {
                    self = .array(value)
                    return
                }
                throw DecodingError.typeMismatch(
                    MessageValue.self,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported auth error format")
                )
            }
        }

        var resolvedMessage: String {
            switch message {
            case .string(let value):
                return value
            case .array(let values):
                return values.joined(separator: ", ")
            case nil:
                return error ?? "Auth request failed."
            }
        }
    }

    private let configuration: AuthConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let clientMetadata: AuthClientMetadata
    private let diagnostics: any AuthDiagnosticsLogging
    private let diagnosticsContext: AuthDiagnosticsContext
    private let httpDateFormatter: DateFormatter

    init(
        configuration: AuthConfiguration,
        session: URLSession = .shared,
        clientMetadata: AuthClientMetadata = .live(),
        diagnostics: any AuthDiagnosticsLogging = AuthDiagnosticsLogger()
    ) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = Self.makeDecoder()
        self.clientMetadata = clientMetadata
        self.diagnostics = diagnostics
        self.diagnosticsContext = AuthDiagnosticsContext(configuration: configuration)
        self.httpDateFormatter = Self.makeHTTPDateFormatter()
    }

    func signInWithApple(request: AppleAuthRequest) async throws -> AuthNetworkResult<AuthResponse> {
        try await performRequest(operation: .appleSignIn, body: request)
    }

    func refresh(refreshToken: String) async throws -> AuthNetworkResult<AuthResponse> {
        try await performRequest(operation: .refresh, body: RefreshTokenRequest(refreshToken: refreshToken))
    }

    func logout(refreshToken: String) async throws -> AuthNetworkResult<LogoutResponse> {
        try await performRequest(operation: .logout, body: RefreshTokenRequest(refreshToken: refreshToken))
    }

    func me(accessToken: String) async throws -> AuthNetworkResult<AuthUser> {
        try await performRequest(operation: .me, accessToken: accessToken)
    }

    private func performRequest<Response: Decodable & Sendable, Body: Encodable>(
        operation: AuthRequestOperation,
        body: Body? = nil,
        accessToken: String? = nil
    ) async throws -> AuthNetworkResult<Response> {
        let clientRequestId = UUID().uuidString
        let startedAt = Date()
        let request = try makeRequest(
            operation: operation,
            clientRequestId: clientRequestId,
            body: body,
            accessToken: accessToken
        )

        diagnostics.log(
            .info,
            phase: "auth.request.started",
            operation: operation,
            requestId: clientRequestId,
            backendRequestId: nil,
            details: requestLogDetails(operation: operation, body: body, accessToken: accessToken)
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                let mappedError = AuthServiceError.invalidResponse(requestId: clientRequestId)
                diagnostics.log(
                    .error,
                    phase: "auth.request.failed",
                    operation: operation,
                    requestId: clientRequestId,
                    backendRequestId: nil,
                    details: errorLogDetails(for: mappedError, durationSince: startedAt)
                )
                throw mappedError
            }

            let responseRequestId = httpResponse.value(forHTTPHeaderField: "x-request-id")
            let duration = durationMilliseconds(since: startedAt)

            diagnostics.log(
                .info,
                phase: "auth.response.received",
                operation: operation,
                requestId: clientRequestId,
                backendRequestId: responseRequestId,
                details: diagnosticsContext.fields(
                    endpoint: "/" + operation.path,
                    statusCode: httpResponse.statusCode,
                    requestId: responseRequestId ?? clientRequestId
                )
                    .merging(["durationMs": String(duration)]) { _, newValue in
                        newValue
                    }
            )

            if let serviceError = mapHTTPError(
                statusCode: httpResponse.statusCode,
                responseData: data,
                requestId: responseRequestId,
                retryAfterHeader: httpResponse.value(forHTTPHeaderField: "Retry-After")
            ) {
                diagnostics.log(
                    .warning,
                    phase: "auth.request.failed",
                    operation: operation,
                    requestId: clientRequestId,
                    backendRequestId: responseRequestId,
                    details: httpFailureLogDetails(
                        operation: operation,
                        response: httpResponse,
                        responseData: data,
                        error: serviceError,
                        clientRequestId: clientRequestId,
                        durationSince: startedAt
                    )
                )
                throw serviceError
            }

            do {
                let decoded = try decoder.decode(Response.self, from: data)
                if let authResponse = decoded as? AuthResponse {
                    diagnostics.log(
                        .info,
                        phase: "auth.tokens.received",
                        operation: operation,
                        requestId: clientRequestId,
                        backendRequestId: responseRequestId,
                        details: AuthDiagnosticsFields.token("accessToken", value: authResponse.accessToken)
                            .merging(AuthDiagnosticsFields.token("refreshToken", value: authResponse.refreshToken)) { _, newValue in
                                newValue
                            }
                    )
                }

                return AuthNetworkResult(
                    value: decoded,
                    metadata: AuthResponseMetadata(
                        statusCode: httpResponse.statusCode,
                        requestId: responseRequestId,
                        clientRequestId: clientRequestId,
                        durationMilliseconds: duration
                    )
                )
            } catch {
                let mappedError = AuthServiceError.decodingFailed(requestId: responseRequestId ?? clientRequestId)
                diagnostics.log(
                    .error,
                    phase: "auth.request.failed",
                    operation: operation,
                    requestId: clientRequestId,
                    backendRequestId: responseRequestId,
                    details: errorLogDetails(for: mappedError, durationSince: startedAt)
                )
                throw mappedError
            }
        } catch let error as AuthServiceError {
            throw error
        } catch {
            let mappedError = AuthServiceError.transport(AuthTransportError.from(error))
            diagnostics.log(
                AuthErrorMapper.presentation(for: mappedError).shouldPresentToast ? .warning : .info,
                phase: "auth.request.failed",
                operation: operation,
                requestId: clientRequestId,
                backendRequestId: nil,
                details: errorLogDetails(for: mappedError, durationSince: startedAt)
            )
            throw mappedError
        }
    }

    private func performRequest<Response: Decodable & Sendable>(
        operation: AuthRequestOperation,
        accessToken: String? = nil
    ) async throws -> AuthNetworkResult<Response> {
        try await performRequest(operation: operation, body: Optional<String>.none, accessToken: accessToken)
    }

    private func makeRequest<Body: Encodable>(
        operation: AuthRequestOperation,
        clientRequestId: String,
        body: Body?,
        accessToken: String?
    ) throws -> URLRequest {
        let url = configuration.baseURL.appending(path: operation.path)
        var request = URLRequest(url: url)
        request.httpMethod = operation.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientRequestId, forHTTPHeaderField: "x-request-id")
        request.setValue(clientMetadata.platform, forHTTPHeaderField: "x-platform")
        request.setValue(clientMetadata.appVersion, forHTTPHeaderField: "x-app-version")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func requestLogDetails<Body: Encodable>(
        operation: AuthRequestOperation,
        body: Body?,
        accessToken: String?
    ) -> [String: String] {
        var details: [String: String] = [
            "appVersion": clientMetadata.appVersion,
            "backendBaseURL": diagnosticsContext.backendBaseURL,
            "region": diagnosticsContext.region,
            "endpoint": "/" + operation.path,
            "method": operation.method,
            "path": "/" + operation.path,
            "platform": clientMetadata.platform
        ]

        if let appleRequest = body as? AppleAuthRequest {
            details.merge(AuthDiagnosticsFields.token("identityToken", value: appleRequest.identityToken)) { _, newValue in
                newValue
            }
            details.merge(AuthDiagnosticsFields.optionalString("email", value: appleRequest.email)) { _, newValue in
                newValue
            }
            details.merge(AuthDiagnosticsFields.optionalString("firstName", value: appleRequest.firstName)) { _, newValue in
                newValue
            }
            details.merge(AuthDiagnosticsFields.optionalString("lastName", value: appleRequest.lastName)) { _, newValue in
                newValue
            }
        }

        if let refreshRequest = body as? RefreshTokenRequest {
            details.merge(AuthDiagnosticsFields.token("refreshToken", value: refreshRequest.refreshToken)) { _, newValue in
                newValue
            }
        }

        if let accessToken {
            details.merge(AuthDiagnosticsFields.token("authorizationToken", value: accessToken)) { _, newValue in
                newValue
            }
        }

        return details
    }

    private func mapHTTPError(
        statusCode: Int,
        responseData: Data,
        requestId: String?,
        retryAfterHeader: String?
    ) -> AuthServiceError? {
        guard !(200..<300).contains(statusCode) else {
            return nil
        }

        let envelope = try? decoder.decode(ErrorEnvelope.self, from: responseData)
        let message = envelope?.resolvedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMessage = (message?.isEmpty == false)
            ? message!
            : HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let retryAfter = resolveRetryAfter(from: retryAfterHeader)

        switch statusCode {
        case 401:
            return .unauthorized(requestId: requestId)
        case 403:
            return .forbidden(requestId: requestId, message: resolvedMessage)
        case 429:
            return .rateLimited(requestId: requestId, message: resolvedMessage, retryAfter: retryAfter)
        case 500...599:
            return .server(statusCode: statusCode, message: resolvedMessage, requestId: requestId)
        default:
            return .backend(statusCode: statusCode, message: resolvedMessage, requestId: requestId)
        }
    }

    private func errorLogDetails(for error: AuthServiceError, durationSince startedAt: Date) -> [String: String] {
        [
            "durationMs": String(durationMilliseconds(since: startedAt)),
            "errorType": String(describing: AuthErrorMapper.category(for: error).rawValue),
            "message": error.localizedDescription
        ]
    }

    private func httpFailureLogDetails(
        operation: AuthRequestOperation,
        response: HTTPURLResponse,
        responseData: Data,
        error: AuthServiceError,
        clientRequestId: String,
        durationSince startedAt: Date
    ) -> [String: String] {
        let backendRequestId = response.value(forHTTPHeaderField: "x-request-id")
        let backendRegion = response.value(forHTTPHeaderField: "x-millio-region")
        let backendPublicAPIBaseURL = response.value(forHTTPHeaderField: "x-millio-public-api-base-url")
        let rawBody = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedBody = rawBody?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let truncatedBody = sanitizedBody.map { String($0.prefix(600)) }

        let envelope = try? decoder.decode(ErrorEnvelope.self, from: responseData)
        let message = envelope?.resolvedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMessage = (message?.isEmpty == false)
            ? message!
            : HTTPURLResponse.localizedString(forStatusCode: response.statusCode)

        var details = diagnosticsContext.fields(
            endpoint: "/" + operation.path,
            statusCode: response.statusCode,
            requestId: backendRequestId ?? clientRequestId,
            errorType: AuthErrorMapper.category(for: error).rawValue,
            reason: resolvedMessage
        )

        details["durationMs"] = String(durationMilliseconds(since: startedAt))
        details["status"] = String(response.statusCode)
        details["message"] = resolvedMessage
        if let backendRequestId, !backendRequestId.isEmpty {
            details["x-request-id"] = backendRequestId
        }
        if let backendRegion, !backendRegion.isEmpty {
            details["x-millio-region"] = backendRegion
        }
        if let backendPublicAPIBaseURL, !backendPublicAPIBaseURL.isEmpty {
            details["x-millio-public-api-base-url"] = backendPublicAPIBaseURL
        }
        if let truncatedBody, !truncatedBody.isEmpty {
            details["responseBody"] = truncatedBody
        }

        return details
    }

    private func durationMilliseconds(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1_000)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = formatter.date(from: raw) ?? fallbackFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(raw)")
        }
        return decoder
    }

    private static func makeHTTPDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }

    private func resolveRetryAfter(from header: String?) -> TimeInterval? {
        guard let rawHeader = header?.trimmingCharacters(in: .whitespacesAndNewlines), !rawHeader.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(rawHeader), seconds > 0 {
            return seconds
        }

        guard let date = httpDateFormatter.date(from: rawHeader) else {
            return nil
        }

        return max(date.timeIntervalSinceNow, 0)
    }
}

protocol AuthServiceProtocol: Sendable {
    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession
    func restoreSession() async throws -> AuthSession?
    func lastKnownSession() async -> AuthSession?
    func currentUser() async throws -> AuthUser
    func logout() async
    func accessTokenExpiryDate() async -> Date?
    func accessToken(forceRefresh: Bool) async throws -> String
}

actor AuthService: AuthServiceProtocol {
    private let apiClient: any AuthAPIClientProtocol
    private let tokenStore: AuthTokenStore
    private let sessionSnapshotStore: any AuthSessionSnapshotStoreProtocol
    private let diagnostics: any AuthDiagnosticsLogging
    private let diagnosticsContext: AuthDiagnosticsContext
    private var signInBackoffState = AuthRateLimitBackoffState()
    private var refreshBackoffState = AuthRateLimitBackoffState()
    private var activeRefreshTask: Task<String, Error>?

    init(
        apiClient: any AuthAPIClientProtocol,
        tokenStore: AuthTokenStore = AuthTokenStore(),
        sessionSnapshotStore: any AuthSessionSnapshotStoreProtocol = UserDefaultsAuthSessionSnapshotStore(),
        diagnostics: any AuthDiagnosticsLogging = AuthDiagnosticsLogger(),
        diagnosticsContext: AuthDiagnosticsContext = .empty
    ) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.sessionSnapshotStore = sessionSnapshotStore
        self.diagnostics = diagnostics
        self.diagnosticsContext = diagnosticsContext
    }

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        let trimmedToken = identityToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw AuthServiceError.invalidIdentityToken
        }

        try throwIfRateLimited(&signInBackoffState)

        do {
            let response = try await apiClient.signInWithApple(
                request: AppleAuthRequest(
                    identityToken: trimmedToken,
                    email: sanitize(email),
                    firstName: sanitize(firstName),
                    lastName: sanitize(lastName)
                )
            )
            signInBackoffState.reset()
            return try await persist(response, source: .appleSignIn)
        } catch let AuthServiceError.rateLimited(requestId, message, retryAfter) {
            throw registerRateLimit(
                &signInBackoffState,
                requestId: requestId,
                message: message,
                retryAfter: retryAfter,
                operation: .appleSignIn
            )
        }
    }

    func restoreSession() async throws -> AuthSession? {
        guard let refreshToken = try await tokenStore.refreshToken() else {
            try? sessionSnapshotStore.clearSession()
            diagnostics.log(.info, phase: "auth.session.restore.skipped", operation: .refresh, requestId: nil, backendRequestId: nil, details: ["reason": "noRefreshToken"])
            return nil
        }

        do {
            let response = try await apiClient.refresh(refreshToken: refreshToken)
            refreshBackoffState.reset()
            return try await persist(response, source: .refresh)
        } catch AuthServiceError.unauthorized {
            diagnostics.log(.warning, phase: "auth.session.restore.cleared", operation: .refresh, requestId: nil, backendRequestId: nil, details: ["reason": "unauthorized"])
            try await tokenStore.clear()
            try? sessionSnapshotStore.clearSession()
            return nil
        } catch let AuthServiceError.rateLimited(requestId, message, retryAfter) {
            throw registerRateLimit(
                &refreshBackoffState,
                requestId: requestId,
                message: message,
                retryAfter: retryAfter,
                operation: .refresh
            )
        }
    }

    func lastKnownSession() async -> AuthSession? {
        do {
            return try sessionSnapshotStore.session()
        } catch {
            diagnostics.log(
                .warning,
                phase: "auth.session.snapshot.load_failed",
                operation: .refresh,
                requestId: nil,
                backendRequestId: nil,
                details: ["errorType": AuthErrorMapper.category(for: error).rawValue]
            )
            return nil
        }
    }

    func currentUser() async throws -> AuthUser {
        let token = try await validAccessToken()

        do {
            let response = try await apiClient.me(accessToken: token)
            return response.value
        } catch AuthServiceError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            let response = try await apiClient.me(accessToken: refreshedToken)
            return response.value
        }
    }

    func logout() async {
        do {
            if let refreshToken = try await tokenStore.refreshToken() {
                _ = try? await apiClient.logout(refreshToken: refreshToken)
            }
            try await tokenStore.clear()
            try? sessionSnapshotStore.clearSession()
            diagnostics.log(.info, phase: "auth.logout.local_state_cleared", operation: .logout, requestId: nil, backendRequestId: nil, details: [:])
        } catch {
            diagnostics.log(.warning, phase: "auth.logout.cleanup_failed", operation: .logout, requestId: nil, backendRequestId: nil, details: ["errorType": AuthErrorMapper.category(for: error).rawValue])
            try? await tokenStore.clear()
            try? sessionSnapshotStore.clearSession()
        }
    }

    func accessTokenExpiryDate() async -> Date? {
        await tokenStore.accessTokenExpiresAt()
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        if forceRefresh {
            return try await refreshAccessToken()
        }
        return try await validAccessToken()
    }

    private func validAccessToken() async throws -> String {
        if let token = await tokenStore.accessToken() {
            return token
        }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        // Coalesce concurrent refresh calls — only one in-flight at a time.
        // Assigning activeRefreshTask before any `await` keeps this atomic within the actor.
        if let task = activeRefreshTask {
            return try await task.value
        }
        let task = Task<String, Error> { [self] in
            try await self.performRefresh()
        }
        activeRefreshTask = task
        do {
            let token = try await task.value
            activeRefreshTask = nil
            return token
        } catch {
            activeRefreshTask = nil
            throw error
        }
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = try await tokenStore.refreshToken() else {
            throw AuthServiceError.notAuthenticated
        }

        try throwIfRateLimited(&refreshBackoffState)

        do {
            let response = try await apiClient.refresh(refreshToken: refreshToken)
            refreshBackoffState.reset()
            _ = try await persist(response, source: .refresh)
            guard let token = await tokenStore.accessToken() else {
                throw AuthServiceError.notAuthenticated
            }
            return token
        } catch AuthServiceError.unauthorized {
            try await tokenStore.clear()
            try? sessionSnapshotStore.clearSession()
            throw AuthServiceError.unauthorized()
        } catch let AuthServiceError.rateLimited(requestId, message, retryAfter) {
            throw registerRateLimit(
                &refreshBackoffState,
                requestId: requestId,
                message: message,
                retryAfter: retryAfter,
                operation: .refresh
            )
        }
    }

    private func persist(
        _ result: AuthNetworkResult<AuthResponse>,
        source: AuthSessionSource
    ) async throws -> AuthSession {
        diagnostics.log(
            .info,
            phase: "tokens_persist_started",
            operation: source.operation,
            requestId: result.metadata.clientRequestId,
            backendRequestId: result.metadata.requestId,
            details: diagnosticsContext.fields(
                endpoint: "/" + source.operation.path,
                statusCode: result.metadata.statusCode,
                requestId: result.metadata.requestId ?? result.metadata.clientRequestId,
                reason: "Persisting auth tokens"
            )
        )

        do {
            let session = try await tokenStore.store(
                result.value,
                metadata: result.metadata,
                source: source
            )
            do {
                try sessionSnapshotStore.setSession(session)
            } catch {
                diagnostics.log(
                    .warning,
                    phase: "auth.session.snapshot.persist_failed",
                    operation: source.operation,
                    requestId: result.metadata.clientRequestId,
                    backendRequestId: result.metadata.requestId,
                    details: ["errorType": AuthErrorMapper.category(for: error).rawValue]
                )
            }
            diagnostics.log(
                .info,
                phase: "tokens_persist_succeeded",
                operation: source.operation,
                requestId: result.metadata.clientRequestId,
                backendRequestId: result.metadata.requestId,
                details: diagnosticsContext.fields(
                    endpoint: "/" + source.operation.path,
                    statusCode: result.metadata.statusCode,
                    requestId: result.metadata.requestId ?? result.metadata.clientRequestId,
                    reason: "Auth tokens persisted"
                )
                    .merging([
                        "accessTokenStored": "true",
                        "refreshTokenStored": "true",
                        "expiresAt": ISO8601DateFormatter().string(from: session.accessTokenExpiresAt)
                    ]) { _, newValue in
                        newValue
                    }
            )
            return session
        } catch {
            let mappedError = (error as? AuthServiceError) ?? AuthServiceError.tokenPersistenceFailed(error.localizedDescription)
            diagnostics.log(
                .error,
                phase: "auth.tokens.persist_failed",
                operation: source.operation,
                requestId: result.metadata.clientRequestId,
                backendRequestId: result.metadata.requestId,
                details: diagnosticsContext.fields(
                    endpoint: "/" + source.operation.path,
                    statusCode: result.metadata.statusCode,
                    requestId: result.metadata.requestId ?? result.metadata.clientRequestId,
                    errorType: AuthErrorMapper.category(for: mappedError).rawValue,
                    reason: mappedError.localizedDescription
                )
            )
            throw mappedError
        }
    }

    private func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func throwIfRateLimited(_ state: inout AuthRateLimitBackoffState) throws {
        if let error = state.failFastError() {
            throw error
        }
    }

    private func registerRateLimit(
        _ state: inout AuthRateLimitBackoffState,
        requestId: String?,
        message: String,
        retryAfter: TimeInterval?,
        operation: AuthRequestOperation
    ) -> AuthServiceError {
        let error = state.registerRateLimit(
            requestId: requestId,
            message: message,
            retryAfter: retryAfter
        )
        if case let .rateLimited(_, _, effectiveRetryAfter) = error {
            diagnostics.log(
                .warning,
                phase: "auth.rate_limit.backoff_started",
                operation: operation,
                requestId: nil,
                backendRequestId: requestId,
                details: ["retryAfterSeconds": String(format: "%.3f", effectiveRetryAfter ?? 0)]
            )
        }
        return error
    }
}

struct UnconfiguredAuthService: AuthServiceProtocol {
    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        throw AuthServiceError.unconfigured
    }

    func restoreSession() async throws -> AuthSession? {
        throw AuthServiceError.unconfigured
    }

    func lastKnownSession() async -> AuthSession? {
        nil
    }

    func currentUser() async throws -> AuthUser {
        throw AuthServiceError.unconfigured
    }

    func logout() async {}

    func accessTokenExpiryDate() async -> Date? {
        nil
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        throw AuthServiceError.unconfigured
    }
}

@MainActor
@Observable
final class AuthManager {
    var status: AuthManagerStatus = .signedOut
    var currentUser: AuthUser?
    var errorMessage: String?
    var isBusy: Bool = false
    var isLogoutInProgress: Bool = false
    var accessTokenExpiresAt: Date?

    var isAuthenticated: Bool {
        status == .authenticated && currentUser != nil
    }

    @ObservationIgnored
    private var service: any AuthServiceProtocol
    @ObservationIgnored
    private var toastCenter: ToastCenter?
    @ObservationIgnored
    private let diagnostics: any AuthDiagnosticsLogging
    @ObservationIgnored
    private let authorizationExtractor: any AppleAuthorizationExtracting
    @ObservationIgnored
    private var lastAuthRequestId: String?
    @ObservationIgnored
    private var lastResolvedRoute: RootViewRoute?
    @ObservationIgnored
    private var onSessionChanged: (@MainActor @Sendable (AuthUser?) async -> Void)?
    @ObservationIgnored
    private var onPostLoginBootstrap: (@MainActor @Sendable (AuthUser) async throws -> Void)?
    @ObservationIgnored
    private var diagnosticsContext: AuthDiagnosticsContext = .empty
    @ObservationIgnored
    private var activeAppleSignInAttemptID: UUID?
    @ObservationIgnored
    private var isAppleSignInSubmitting = false

    init(
        service: any AuthServiceProtocol = UnconfiguredAuthService(),
        toastCenter: ToastCenter? = nil,
        diagnostics: any AuthDiagnosticsLogging = AuthDiagnosticsLogger(),
        authorizationExtractor: any AppleAuthorizationExtracting = AppleAuthorizationExtractor()
    ) {
        self.service = service
        self.toastCenter = toastCenter
        self.diagnostics = diagnostics
        self.authorizationExtractor = authorizationExtractor
    }

    func configure(service: any AuthServiceProtocol) {
        self.service = service
    }

    func configure(toastCenter: ToastCenter) {
        self.toastCenter = toastCenter
    }

    func configure(onSessionChanged: @escaping @MainActor @Sendable (AuthUser?) async -> Void) {
        self.onSessionChanged = onSessionChanged
    }

    func configure(onPostLoginBootstrap: @escaping @MainActor @Sendable (AuthUser) async throws -> Void) {
        self.onPostLoginBootstrap = onPostLoginBootstrap
    }

    func configure(authConfiguration: AuthConfiguration) {
        diagnosticsContext = AuthDiagnosticsContext(configuration: authConfiguration)
    }

    func markAppleSignInStarted() {
        if isBusy || activeAppleSignInAttemptID != nil {
            diagnostics.log(.warning, phase: "apple_sign_in.ignored_busy", operation: .appleSignIn, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
            return
        }

        clearFeedback()
        isBusy = true
        activeAppleSignInAttemptID = UUID()
        diagnostics.log(
            .info,
            phase: "apple_sign_in_started",
            operation: .appleSignIn,
            requestId: nil,
            backendRequestId: nil,
            details: diagnosticsContext.fields(
                endpoint: "/auth/apple",
                reason: "Apple Sign In flow started"
            )
        )
    }

    func restoreSession() async {
        guard !isBusy else {
            diagnostics.log(.info, phase: "auth.session.restore.skipped_busy", operation: .refresh, requestId: nil, backendRequestId: nil, details: [:])
            return
        }

        status = .restoring
        clearFeedback()
        isBusy = true
        diagnostics.log(.info, phase: "auth.session.restore.started", operation: .refresh, requestId: nil, backendRequestId: nil, details: [:])
        defer { isBusy = false }

        do {
            guard let session = try await service.restoreSession() else {
                clearState()
                diagnostics.log(.info, phase: "auth.session.restore.completed", operation: .refresh, requestId: nil, backendRequestId: nil, details: ["restored": "false"])
                return
            }
            apply(session)
        } catch {
            // Keep the last known signed-in UI state for transient backend/network failures.
            if shouldKeepSessionOnRestoreFailure(error),
               let cachedSession = await service.lastKnownSession() {
                apply(cachedSession)
                present(error, operation: .refresh)
                diagnostics.log(
                    .warning,
                    phase: "auth.session.restore.fallback_snapshot",
                    operation: .refresh,
                    requestId: cachedSession.metadata.clientRequestId,
                    backendRequestId: cachedSession.metadata.requestId,
                    details: ["source": cachedSession.source.rawValue]
                )
                return
            }
            clearState()
            present(error, operation: .refresh)
        }
    }

    func signIn(with authorization: Result<ASAuthorization, Error>) async {
        guard let attemptID = activeAppleSignInAttemptID else {
            diagnostics.log(.warning, phase: "apple_sign_in.ignored_busy", operation: .appleSignIn, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
            return
        }
        guard !isAppleSignInSubmitting else {
            diagnostics.log(.warning, phase: "apple_sign_in.ignored_busy", operation: .appleSignIn, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
            return
        }
        isAppleSignInSubmitting = true
        defer {
            isAppleSignInSubmitting = false
            if activeAppleSignInAttemptID == attemptID {
                activeAppleSignInAttemptID = nil
                isBusy = false
            }
        }

        do {
            let payload = try authorizationExtractor.extract(from: authorization)
            diagnostics.log(
                .info,
                phase: "apple_credential_received",
                operation: .appleSignIn,
                requestId: nil,
                backendRequestId: nil,
                details: diagnosticsContext.fields(
                    endpoint: "/auth/apple",
                    reason: "Apple credential received"
                )
                    .merging(AuthDiagnosticsFields.token("identityToken", value: payload.identityToken)) { _, newValue in
                        newValue
                    }
                    .merging(AuthDiagnosticsFields.optionalString("email", value: payload.email)) { _, newValue in
                        newValue
                    }
                    .merging(AuthDiagnosticsFields.optionalString("firstName", value: payload.firstName)) { _, newValue in
                        newValue
                    }
                    .merging(AuthDiagnosticsFields.optionalString("lastName", value: payload.lastName)) { _, newValue in
                        newValue
                    }
            )

            diagnostics.log(
                .info,
                phase: "auth_request_started",
                operation: .appleSignIn,
                requestId: nil,
                backendRequestId: nil,
                details: diagnosticsContext.fields(
                    endpoint: "/auth/apple",
                    reason: "Submitting /auth/apple"
                )
            )

            let session = try await service.signInWithApple(
                identityToken: payload.identityToken,
                email: payload.email,
                firstName: payload.firstName,
                lastName: payload.lastName
            )
            guard activeAppleSignInAttemptID == attemptID else {
                return
            }
            diagnostics.log(
                .info,
                phase: "auth_request_succeeded",
                operation: .appleSignIn,
                requestId: session.metadata.clientRequestId,
                backendRequestId: session.metadata.requestId,
                details: diagnosticsContext.fields(
                    endpoint: "/auth/apple",
                    statusCode: session.metadata.statusCode,
                    requestId: session.requestId,
                    reason: "Successful /auth/apple response"
                )
            )
            apply(session)
            await runPostLoginBootstrap(for: session)
            diagnostics.log(
                .info,
                phase: "login_flow_completed",
                operation: .appleSignIn,
                requestId: session.metadata.clientRequestId,
                backendRequestId: session.metadata.requestId,
                details: diagnosticsContext.fields(
                    endpoint: "/auth/apple",
                    statusCode: session.metadata.statusCode,
                    requestId: session.requestId,
                    reason: "Login flow completed"
                )
            )
        } catch let error as ASAuthorizationError where error.code == .canceled {
            diagnostics.log(.info, phase: "apple_sign_in.cancelled", operation: .appleSignIn, requestId: nil, backendRequestId: nil, details: [:])
            clearFeedback()
        } catch {
            guard activeAppleSignInAttemptID == attemptID else {
                return
            }
            present(error, operation: .appleSignIn)
        }
    }

    func reloadCurrentUser() async {
        guard isAuthenticated, !isBusy else {
            return
        }

        clearFeedback()
        isBusy = true
        diagnostics.log(.info, phase: "auth.me.started", operation: .me, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
        defer { isBusy = false }

        do {
            let user = try await service.currentUser()
            let tokenExpiryDate = await service.accessTokenExpiryDate()

            // If session changed while request was in-flight (e.g. user logged out),
            // do not restore stale authenticated state.
            guard isAuthenticated else {
                diagnostics.log(.info, phase: "auth.me.ignored_after_state_change", operation: .me, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
                return
            }

            currentUser = user
            accessTokenExpiresAt = tokenExpiryDate
            diagnostics.log(.info, phase: "auth.me.completed", operation: .me, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
        } catch {
            present(error, operation: .me)
            if case AuthServiceError.unauthorized = error {
                clearState()
            }
        }
    }

    func logout() async {
        guard isAuthenticated, !isLogoutInProgress else { return }

        let wasBusy = isBusy
        isBusy = true
        isLogoutInProgress = true
        diagnostics.log(.info, phase: "auth.logout.started", operation: .logout, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
        defer {
            isLogoutInProgress = false
            if !wasBusy {
                isBusy = false
            }
        }

        await service.logout()
        clearState()
        await onSessionChanged?(nil)
    }

    func logResolvedRoute(_ route: RootViewRoute) {
        guard route != lastResolvedRoute else { return }
        lastResolvedRoute = route

        let isAuthorizedRoute = route == .onboarding || route == .ready || route == .restoring || route == .autoRestoring
        guard isAuthenticated, isAuthorizedRoute else { return }

        diagnostics.log(
            .info,
            phase: "auth.navigation.authorized_route",
            operation: nil,
            requestId: lastAuthRequestId,
            backendRequestId: nil,
            details: ["route": String(describing: route)]
        )
    }

    func dismissToast() {
        toastCenter?.dismiss()
        errorMessage = nil
    }

    private func apply(_ session: AuthSession) {
        currentUser = session.user
        accessTokenExpiresAt = session.accessTokenExpiresAt
        lastAuthRequestId = session.requestId
        status = .authenticated
        clearFeedback()

        diagnostics.log(
            .info,
            phase: "auth.session.updated",
            operation: session.source.operation,
            requestId: session.metadata.clientRequestId,
            backendRequestId: session.metadata.requestId,
            details: [
                "authenticated": "true",
                "source": session.source.rawValue
            ]
        )

        Task { @MainActor [onSessionChanged, user = session.user] in
            await onSessionChanged?(user)
        }
    }

    private func clearState() {
        currentUser = nil
        accessTokenExpiresAt = nil
        status = .signedOut
        lastAuthRequestId = nil
    }

    private func clearFeedback() {
        errorMessage = nil
        dismissToast()
    }

    private func present(_ error: Error, operation: AuthRequestOperation?) {
        let presentation = AuthErrorMapper.presentation(for: error, operation: operation)
        errorMessage = presentation.message

        if presentation.shouldPresentToast, let message = presentation.message {
            toastCenter?.show(message: message)
        } else {
            toastCenter?.dismiss()
        }

        diagnostics.log(
            presentation.shouldPresentToast ? .warning : .info,
            phase: "auth.error.presented",
            operation: operation,
            requestId: (error as? AuthServiceError)?.requestId ?? lastAuthRequestId,
            backendRequestId: (error as? AuthServiceError)?.requestId,
            details: [
                "category": presentation.category.rawValue,
                "toast": presentation.shouldPresentToast ? "true" : "false"
            ]
        )
    }

    private func shouldKeepSessionOnRestoreFailure(_ error: Error) -> Bool {
        switch AuthErrorMapper.category(for: error) {
        case .noInternet, .timeout, .tls, .transport, .rateLimited, .serverUnavailable, .serviceUnavailable:
            return true
        case .requestCancelled, .unauthorized, .forbidden, .invalidResponse, .tokenPersistence, .appleCredentials, .business, .postLoginBootstrap, .wrongSessionNamespace, .unknown:
            return false
        }
    }

    // Post-login work is allowed to fail without tearing down a valid session.
    private func runPostLoginBootstrap(for session: AuthSession) async {
        guard let onPostLoginBootstrap else { return }

        diagnostics.log(
            .info,
            phase: "post_login_bootstrap_started",
            operation: .me,
            requestId: session.metadata.clientRequestId,
            backendRequestId: session.metadata.requestId,
            details: diagnosticsContext.fields(
                endpoint: "/auth/me",
                requestId: session.requestId,
                reason: "Running post-login bootstrap"
            )
        )

        do {
            try await onPostLoginBootstrap(session.user)
        } catch AuthServiceError.unauthorized {
            let error = AuthFlowError.wrongSessionNamespace
            diagnostics.log(
                .error,
                phase: "post_login_bootstrap_failed",
                operation: .me,
                requestId: session.metadata.clientRequestId,
                backendRequestId: session.metadata.requestId,
                details: diagnosticsContext.fields(
                    endpoint: "/auth/me",
                    requestId: session.requestId,
                    errorType: AuthErrorMapper.category(for: error).rawValue,
                    reason: error.localizedDescription
                )
            )
            present(error, operation: .me)
        } catch {
            let flowError = AuthFlowError.postLoginBootstrapFailed(error.localizedDescription)
            diagnostics.log(
                .error,
                phase: "post_login_bootstrap_failed",
                operation: .me,
                requestId: session.metadata.clientRequestId,
                backendRequestId: session.metadata.requestId,
                details: diagnosticsContext.fields(
                    endpoint: "/auth/me",
                    requestId: session.requestId,
                    errorType: AuthErrorMapper.category(for: flowError).rawValue,
                    reason: error.localizedDescription
                )
            )
            present(flowError, operation: .me)
        }
    }
}
