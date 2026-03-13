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

protocol RefreshTokenStoreProtocol: Sendable {
    func refreshToken() throws -> String?
    func setRefreshToken(_ value: String) throws
    func clearRefreshToken() throws
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
        requestId: String? = nil,
        source: AuthSessionSource
    ) throws -> AuthSession {
        let expiresAt = now.addingTimeInterval(TimeInterval(response.accessTokenExpiresInSeconds))
        accessTokenState = AccessTokenState(value: response.accessToken, expiresAt: expiresAt)
        try refreshTokenStore.setRefreshToken(response.refreshToken)
        return AuthSession(
            user: response.user,
            accessTokenExpiresAt: expiresAt,
            requestId: requestId,
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
                details: [
                    "durationMs": String(duration),
                    "statusCode": String(httpResponse.statusCode)
                ]
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
                    details: errorLogDetails(for: serviceError, durationSince: startedAt)
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
            "errorType": String(describing: AuthErrorMapper.category(for: error).rawValue)
        ]
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
    func currentUser() async throws -> AuthUser
    func logout() async
    func accessTokenExpiryDate() async -> Date?
    func accessToken(forceRefresh: Bool) async throws -> String
}

actor AuthService: AuthServiceProtocol {
    private let apiClient: any AuthAPIClientProtocol
    private let tokenStore: AuthTokenStore
    private let diagnostics: any AuthDiagnosticsLogging
    private var signInBackoffState = AuthRateLimitBackoffState()
    private var refreshBackoffState = AuthRateLimitBackoffState()

    init(
        apiClient: any AuthAPIClientProtocol,
        tokenStore: AuthTokenStore = AuthTokenStore(),
        diagnostics: any AuthDiagnosticsLogging = AuthDiagnosticsLogger()
    ) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.diagnostics = diagnostics
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
            diagnostics.log(.info, phase: "auth.logout.local_state_cleared", operation: .logout, requestId: nil, backendRequestId: nil, details: [:])
        } catch {
            diagnostics.log(.warning, phase: "auth.logout.cleanup_failed", operation: .logout, requestId: nil, backendRequestId: nil, details: ["errorType": AuthErrorMapper.category(for: error).rawValue])
            try? await tokenStore.clear()
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
        do {
            let session = try await tokenStore.store(
                result.value,
                requestId: result.metadata.requestId ?? result.metadata.clientRequestId,
                source: source
            )
            diagnostics.log(
                .info,
                phase: "auth.tokens.persisted",
                operation: source.operation,
                requestId: result.metadata.clientRequestId,
                backendRequestId: result.metadata.requestId,
                details: [
                    "accessTokenStored": "true",
                    "refreshTokenStored": "true",
                    "expiresAt": ISO8601DateFormatter().string(from: session.accessTokenExpiresAt)
                ]
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
                details: ["errorType": AuthErrorMapper.category(for: mappedError).rawValue]
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

    func markAppleSignInStarted() {
        if isBusy {
            diagnostics.log(.warning, phase: "apple_sign_in.ignored_busy", operation: .appleSignIn, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
            return
        }

        diagnostics.log(.info, phase: "apple_sign_in.started", operation: .appleSignIn, requestId: nil, backendRequestId: nil, details: [:])
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
            clearState()
            present(error, operation: .refresh)
        }
    }

    func signIn(with authorization: Result<ASAuthorization, Error>) async {
        guard !isBusy else {
            diagnostics.log(.warning, phase: "apple_sign_in.ignored_busy", operation: .appleSignIn, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
            return
        }

        clearFeedback()
        isBusy = true
        defer { isBusy = false }

        do {
            let payload = try authorizationExtractor.extract(from: authorization)
            diagnostics.log(
                .info,
                phase: "apple_sign_in.credential_received",
                operation: .appleSignIn,
                requestId: nil,
                backendRequestId: nil,
                details: AuthDiagnosticsFields.token("identityToken", value: payload.identityToken)
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

            let session = try await service.signInWithApple(
                identityToken: payload.identityToken,
                email: payload.email,
                firstName: payload.firstName,
                lastName: payload.lastName
            )
            apply(session)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            diagnostics.log(.info, phase: "apple_sign_in.cancelled", operation: .appleSignIn, requestId: nil, backendRequestId: nil, details: [:])
            clearFeedback()
        } catch {
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
            currentUser = try await service.currentUser()
            accessTokenExpiresAt = await service.accessTokenExpiryDate()
            diagnostics.log(.info, phase: "auth.me.completed", operation: .me, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
        } catch {
            present(error, operation: .me)
            if case AuthServiceError.unauthorized = error {
                clearState()
            }
        }
    }

    func logout() async {
        guard !isBusy else { return }

        isBusy = true
        diagnostics.log(.info, phase: "auth.logout.started", operation: .logout, requestId: lastAuthRequestId, backendRequestId: nil, details: [:])
        defer { isBusy = false }

        await service.logout()
        clearState()
        await onSessionChanged?(nil)
    }

    func logResolvedRoute(_ route: RootViewRoute) {
        guard route != lastResolvedRoute else { return }
        lastResolvedRoute = route

        let isAuthorizedRoute = route == .onboarding || route == .ready || route == .restoring
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
            requestId: session.requestId,
            backendRequestId: session.requestId,
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
        let presentation = AuthErrorMapper.presentation(for: error)
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
}
