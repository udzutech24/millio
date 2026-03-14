import Foundation

enum AuthErrorCategory: String, Equatable, Sendable {
    case noInternet
    case timeout
    case requestCancelled
    case tls
    case transport
    case unauthorized
    case forbidden
    case rateLimited
    case serverUnavailable
    case invalidResponse
    case tokenPersistence
    case appleCredentials
    case business
    case serviceUnavailable
    case postLoginBootstrap
    case wrongSessionNamespace
    case unknown
}

struct AuthErrorPresentation: Equatable, Sendable {
    let category: AuthErrorCategory
    let message: String?
    let shouldPresentToast: Bool
}

enum AuthErrorMapper {
    static func presentation(for error: Error) -> AuthErrorPresentation {
        if let flowError = error as? AuthFlowError {
            return presentation(for: flowError)
        }

        guard let authError = error as? AuthServiceError else {
            return AuthErrorPresentation(
                category: .unknown,
                message: String(
                    localized: "auth.error.generic",
                    defaultValue: "Could not complete sign in. Try again.",
                    comment: "Fallback auth error toast"
                ),
                shouldPresentToast: true
            )
        }

        switch authError {
        case .invalidConfiguration, .unconfigured:
            return .init(
                category: .serviceUnavailable,
                message: String(
                    localized: "auth.error.unavailable",
                    defaultValue: "Sign in is temporarily unavailable.",
                    comment: "Auth service unavailable toast"
                ),
                shouldPresentToast: true
            )
        case .invalidIdentityToken, .unexpectedAuthorizationCredential:
            return .init(
                category: .appleCredentials,
                message: String(
                    localized: "auth.error.apple_credentials",
                    defaultValue: "Could not verify your Apple account. Try again.",
                    comment: "Invalid Apple credentials toast"
                ),
                shouldPresentToast: true
            )
        case .notAuthenticated, .unauthorized:
            return .init(
                category: .unauthorized,
                message: String(
                    localized: "auth.error.session_expired",
                    defaultValue: "Your session expired. Sign in again.",
                    comment: "Expired auth session toast"
                ),
                shouldPresentToast: true
            )
        case .forbidden(_, let message):
            return .init(
                category: .forbidden,
                message: resolvedBusinessMessage(
                    message,
                    fallback: String(
                        localized: "auth.error.forbidden",
                        defaultValue: "This account cannot sign in here.",
                        comment: "Forbidden auth toast"
                    )
                ),
                shouldPresentToast: true
            )
        case .rateLimited:
            return .init(
                category: .rateLimited,
                message: String(
                    localized: "auth.error.rate_limited",
                    defaultValue: "Too many attempts. Please wait a bit and try again.",
                    comment: "Rate limited auth toast"
                ),
                shouldPresentToast: true
            )
        case .server:
            return .init(
                category: .serverUnavailable,
                message: String(
                    localized: "auth.error.server",
                    defaultValue: "Server error. Try again later.",
                    comment: "Server auth toast"
                ),
                shouldPresentToast: true
            )
        case .backend(_, let message, _):
            return .init(
                category: .business,
                message: resolvedBusinessMessage(
                    message,
                    fallback: String(
                        localized: "auth.error.generic",
                        defaultValue: "Could not complete sign in. Try again.",
                        comment: "Fallback auth error toast"
                    )
                ),
                shouldPresentToast: true
            )
        case .invalidResponse, .decodingFailed:
            return .init(
                category: .invalidResponse,
                message: String(
                    localized: "auth.error.invalid_response",
                    defaultValue: "Auth response parse failed. Try again.",
                    comment: "Invalid auth response toast"
                ),
                shouldPresentToast: true
            )
        case .tokenPersistenceFailed:
            return .init(
                category: .tokenPersistence,
                message: String(
                    localized: "auth.error.token_persistence",
                    defaultValue: "Token persistence failed. Signed in, but failed to save your session.",
                    comment: "Token persistence failure toast"
                ),
                shouldPresentToast: true
            )
        case .transport(let transportError):
            return presentation(for: transportError)
        }
    }

    static func category(for error: Error) -> AuthErrorCategory {
        presentation(for: error).category
    }

    private static func presentation(for error: AuthTransportError) -> AuthErrorPresentation {
        switch error {
        case .noInternet, .timeout:
            return .init(
                category: error == .timeout ? .timeout : .noInternet,
                message: String(
                    localized: "auth.error.offline",
                    defaultValue: "No internet connection. Check your network and try again.",
                    comment: "Offline auth toast"
                ),
                shouldPresentToast: true
            )
        case .cancelled:
            return .init(category: .requestCancelled, message: nil, shouldPresentToast: false)
        case .tls:
            return .init(
                category: .tls,
                message: String(
                    localized: "auth.error.tls",
                    defaultValue: "Secure connection failed. Check your network and try again.",
                    comment: "TLS auth toast"
                ),
                shouldPresentToast: true
            )
        case .network:
            return .init(
                category: .transport,
                message: String(
                    localized: "auth.error.network",
                    defaultValue: "Network error. Try again.",
                    comment: "Generic network auth toast"
                ),
                shouldPresentToast: true
            )
        }
    }

    private static func presentation(for error: AuthFlowError) -> AuthErrorPresentation {
        switch error {
        case .postLoginBootstrapFailed:
            return .init(
                category: .postLoginBootstrap,
                message: String(
                    localized: "auth.error.post_login_bootstrap",
                    defaultValue: "Post-login bootstrap failed. Your session is active.",
                    comment: "Post-login bootstrap failure toast"
                ),
                shouldPresentToast: true
            )
        case .wrongSessionNamespace:
            return .init(
                category: .wrongSessionNamespace,
                message: String(
                    localized: "auth.error.wrong_session_namespace",
                    defaultValue: "Signed in, but the session belongs to a different backend or region.",
                    comment: "Wrong backend/session namespace toast"
                ),
                shouldPresentToast: true
            )
        }
    }

    private static func resolvedBusinessMessage(_ message: String, fallback: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
