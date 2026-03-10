import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    let id: String
    let email: String?
    let emailVerified: Bool
    let firstName: String?
    let lastName: String?
    let fullName: String?
    let avatarUrl: String?
    let lastLoginAt: Date?
}

struct AuthResponse: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresInSeconds: Int
    let user: AuthUser
}

struct LogoutResponse: Codable, Equatable, Sendable {
    let success: Bool
}

struct AppleAuthRequest: Encodable, Sendable {
    let identityToken: String
    let email: String?
    let firstName: String?
    let lastName: String?
}

struct RefreshTokenRequest: Encodable, Sendable {
    let refreshToken: String
}

enum AuthSessionSource: String, Equatable, Sendable {
    case appleSignIn = "apple_sign_in"
    case refresh

    var operation: AuthRequestOperation {
        switch self {
        case .appleSignIn:
            return .appleSignIn
        case .refresh:
            return .refresh
        }
    }
}

struct AuthSession: Equatable, Sendable {
    let user: AuthUser
    let accessTokenExpiresAt: Date
    let requestId: String?
    let source: AuthSessionSource

    init(
        user: AuthUser,
        accessTokenExpiresAt: Date,
        requestId: String? = nil,
        source: AuthSessionSource = .appleSignIn
    ) {
        self.user = user
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.requestId = requestId
        self.source = source
    }
}

enum AuthManagerStatus: Equatable {
    case signedOut
    case restoring
    case authenticated
}
