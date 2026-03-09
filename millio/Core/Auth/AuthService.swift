@preconcurrency import AuthenticationServices
import Foundation
import Observation
import Security

enum AuthServiceError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidIdentityToken
    case unexpectedAuthorizationCredential
    case notAuthenticated
    case unauthorized
    case backend(statusCode: Int, message: String)
    case transport(String)
    case decodingFailed
    case unconfigured

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "AUTH_BASE_URL is missing or invalid."
        case .invalidIdentityToken:
            return "Apple Sign In did not return a valid identity token."
        case .unexpectedAuthorizationCredential:
            return "Unexpected Apple authorization credential type."
        case .notAuthenticated:
            return "No active authenticated session."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .backend(_, let message):
            return message
        case .transport(let message):
            return message
        case .decodingFailed:
            return "Failed to decode backend auth response."
        case .unconfigured:
            return "Auth service is not configured yet."
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
                throw AuthServiceError.transport("Refresh token is corrupted in Keychain.")
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw AuthServiceError.transport("Keychain read failed with status \(status).")
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
                throw AuthServiceError.transport("Keychain update failed with status \(status).")
            }
            return
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = accessible
        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthServiceError.transport("Keychain save failed with status \(status).")
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
            throw AuthServiceError.transport("Keychain delete failed with status \(status).")
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

    func store(_ response: AuthResponse, now: Date = Date()) throws -> AuthSession {
        let expiresAt = now.addingTimeInterval(TimeInterval(response.accessTokenExpiresInSeconds))
        accessTokenState = AccessTokenState(value: response.accessToken, expiresAt: expiresAt)
        try refreshTokenStore.setRefreshToken(response.refreshToken)
        return AuthSession(user: response.user, accessTokenExpiresAt: expiresAt)
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

protocol AuthAPIClientProtocol: Sendable {
    func signInWithApple(request: AppleAuthRequest) async throws -> AuthResponse
    func refresh(refreshToken: String) async throws -> AuthResponse
    func logout(refreshToken: String) async throws -> LogoutResponse
    func me(accessToken: String) async throws -> AuthUser
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

    init(
        configuration: AuthConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = Self.makeDecoder()
    }

    func signInWithApple(request: AppleAuthRequest) async throws -> AuthResponse {
        try await performRequest(path: "auth/apple", method: "POST", body: request)
    }

    func refresh(refreshToken: String) async throws -> AuthResponse {
        try await performRequest(path: "auth/refresh", method: "POST", body: RefreshTokenRequest(refreshToken: refreshToken))
    }

    func logout(refreshToken: String) async throws -> LogoutResponse {
        try await performRequest(path: "auth/logout", method: "POST", body: RefreshTokenRequest(refreshToken: refreshToken))
    }

    func me(accessToken: String) async throws -> AuthUser {
        try await performRequest(path: "auth/me", method: "GET", accessToken: accessToken)
    }

    private func performRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body? = nil,
        accessToken: String? = nil
    ) async throws -> Response {
        let url = configuration.baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthServiceError.transport("Invalid auth response.")
            }

            if httpResponse.statusCode == 401 {
                throw AuthServiceError.unauthorized
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                    throw AuthServiceError.backend(
                        statusCode: httpResponse.statusCode,
                        message: envelope.resolvedMessage
                    )
                }
                throw AuthServiceError.backend(
                    statusCode: httpResponse.statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                )
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw AuthServiceError.decodingFailed
            }
        } catch let error as AuthServiceError {
            throw error
        } catch {
            throw AuthServiceError.transport(error.localizedDescription)
        }
    }

    private func performRequest<Response: Decodable>(
        path: String,
        method: String,
        accessToken: String? = nil
    ) async throws -> Response {
        try await performRequest(
            path: path,
            method: method,
            body: Optional<String>.none,
            accessToken: accessToken
        )
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

    init(
        apiClient: any AuthAPIClientProtocol,
        tokenStore: AuthTokenStore = AuthTokenStore()
    ) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
    }

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        let trimmedToken = identityToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw AuthServiceError.invalidIdentityToken
        }

        let response = try await apiClient.signInWithApple(
            request: AppleAuthRequest(
                identityToken: trimmedToken,
                email: sanitize(email),
                firstName: sanitize(firstName),
                lastName: sanitize(lastName)
            )
        )
        return try await tokenStore.store(response)
    }

    func restoreSession() async throws -> AuthSession? {
        guard let refreshToken = try await tokenStore.refreshToken() else {
            return nil
        }

        do {
            let response = try await apiClient.refresh(refreshToken: refreshToken)
            return try await tokenStore.store(response)
        } catch AuthServiceError.unauthorized {
            try await tokenStore.clear()
            return nil
        }
    }

    func currentUser() async throws -> AuthUser {
        let token = try await validAccessToken()

        do {
            return try await apiClient.me(accessToken: token)
        } catch AuthServiceError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await apiClient.me(accessToken: refreshedToken)
        }
    }

    func logout() async {
        do {
            if let refreshToken = try await tokenStore.refreshToken() {
                _ = try? await apiClient.logout(refreshToken: refreshToken)
            }
            try await tokenStore.clear()
        } catch {
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

        do {
            let response = try await apiClient.refresh(refreshToken: refreshToken)
            _ = try await tokenStore.store(response)
            guard let token = await tokenStore.accessToken() else {
                throw AuthServiceError.notAuthenticated
            }
            return token
        } catch AuthServiceError.unauthorized {
            try await tokenStore.clear()
            throw AuthServiceError.unauthorized
        }
    }

    private func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    init(
        service: any AuthServiceProtocol = UnconfiguredAuthService(),
        toastCenter: ToastCenter? = nil
    ) {
        self.service = service
        self.toastCenter = toastCenter
    }

    func configure(service: any AuthServiceProtocol) {
        self.service = service
    }

    func configure(toastCenter: ToastCenter) {
        self.toastCenter = toastCenter
    }

    func restoreSession() async {
        guard !isBusy else { return }

        status = .restoring
        clearFeedback()
        isBusy = true
        defer { isBusy = false }

        do {
            guard let session = try await service.restoreSession() else {
                clearState()
                return
            }
            apply(session)
        } catch {
            clearState()
            present(error)
        }
    }

    func signIn(with authorization: Result<ASAuthorization, Error>) async {
        guard !isBusy else { return }

        clearFeedback()
        isBusy = true
        defer { isBusy = false }

        do {
            let session = try await session(for: authorization)
            apply(session)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            clearFeedback()
        } catch {
            present(error)
        }
    }

    func reloadCurrentUser() async {
        guard isAuthenticated, !isBusy else { return }

        clearFeedback()
        isBusy = true
        defer { isBusy = false }

        do {
            currentUser = try await service.currentUser()
            accessTokenExpiresAt = await service.accessTokenExpiryDate()
        } catch {
            present(error)
            if case AuthServiceError.unauthorized = error {
                clearState()
            }
        }
    }

    func logout() async {
        guard !isBusy else { return }

        isBusy = true
        defer { isBusy = false }

        await service.logout()
        clearState()
    }

    private func session(for authorization: Result<ASAuthorization, Error>) async throws -> AuthSession {
        let authorization = try authorization.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthServiceError.unexpectedAuthorizationCredential
        }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthServiceError.invalidIdentityToken
        }

        return try await service.signInWithApple(
            identityToken: identityToken,
            email: credential.email,
            firstName: credential.fullName?.givenName,
            lastName: credential.fullName?.familyName
        )
    }

    private func apply(_ session: AuthSession) {
        currentUser = session.user
        accessTokenExpiresAt = session.accessTokenExpiresAt
        status = .authenticated
        clearFeedback()
    }

    private func clearState() {
        currentUser = nil
        accessTokenExpiresAt = nil
        status = .signedOut
    }

    func dismissToast() {
        toastCenter?.dismiss()
        errorMessage = nil
    }

    private func clearFeedback() {
        errorMessage = nil
        dismissToast()
    }

    private func present(_ error: Error) {
        let message = userFacingMessage(for: error)
        errorMessage = message
        toastCenter?.show(message: message)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let authError = error as? AuthServiceError {
            return userFacingMessage(for: authError)
        }
        return String(
            localized: "auth.error.generic",
            defaultValue: "Could not complete sign in. Try again.",
            comment: "Fallback auth error toast"
        )
    }

    private func userFacingMessage(for error: AuthServiceError) -> String {
        switch error {
        case .invalidConfiguration, .unconfigured:
            return String(
                localized: "auth.error.unavailable",
                defaultValue: "Sign in is temporarily unavailable.",
                comment: "Auth service unavailable toast"
            )
        case .invalidIdentityToken, .unexpectedAuthorizationCredential:
            return String(
                localized: "auth.error.apple_credentials",
                defaultValue: "Could not verify your Apple account. Try again.",
                comment: "Invalid Apple credentials toast"
            )
        case .notAuthenticated, .unauthorized:
            return String(
                localized: "auth.error.session_expired",
                defaultValue: "Your session expired. Sign in again.",
                comment: "Expired auth session toast"
            )
        case .decodingFailed:
            return String(
                localized: "auth.error.invalid_response",
                defaultValue: "Server returned an invalid response. Try again later.",
                comment: "Invalid auth response toast"
            )
        case .transport(let message):
            let normalized = message.lowercased()
            if normalized.contains("internet") || normalized.contains("offline") || normalized.contains("network") {
                return String(
                    localized: "auth.error.offline",
                    defaultValue: "No internet connection. Check your network and try again.",
                    comment: "Offline auth toast"
                )
            }
            if normalized.contains("timed out") || normalized.contains("timeout") {
                return String(
                    localized: "auth.error.timeout",
                    defaultValue: "Server is taking too long to respond. Try again.",
                    comment: "Timed out auth toast"
                )
            }
            return String(
                localized: "auth.error.network",
                defaultValue: "Network error. Try again.",
                comment: "Generic network auth toast"
            )
        case .backend(let statusCode, let message):
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if statusCode == 401 || normalized.contains("invalid apple identity token") {
                return String(
                    localized: "auth.error.apple_credentials",
                    defaultValue: "Could not verify your Apple account. Try again.",
                    comment: "Invalid Apple credentials toast"
                )
            }
            if statusCode == 429 {
                return String(
                    localized: "auth.error.rate_limited",
                    defaultValue: "Too many attempts. Please wait a bit and try again.",
                    comment: "Rate limited auth toast"
                )
            }
            if statusCode >= 500 || normalized == "internal server error" {
                return String(
                    localized: "auth.error.server",
                    defaultValue: "Server error. Try again later.",
                    comment: "Server auth toast"
                )
            }
            if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
            return String(
                localized: "auth.error.generic",
                defaultValue: "Could not complete sign in. Try again.",
                comment: "Fallback auth error toast"
            )
        }
    }
}
