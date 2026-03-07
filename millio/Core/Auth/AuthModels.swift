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

struct AuthSession: Equatable, Sendable {
    let user: AuthUser
    let accessTokenExpiresAt: Date
}

enum AuthManagerStatus: Equatable {
    case signedOut
    case restoring
    case authenticated
}
