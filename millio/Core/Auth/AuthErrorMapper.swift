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
    static func presentation(for error: Error, operation: AuthRequestOperation? = nil) -> AuthErrorPresentation {
        if let flowError = error as? AuthFlowError {
            return presentation(for: flowError)
        }

        guard let authError = error as? AuthServiceError else {
            return AuthErrorPresentation(
                category: .unknown,
                message: L(
                    "auth.error.generic",
                    defaultValue: "Could not complete sign in. Try again."
                ),
                shouldPresentToast: true
            )
        }

        switch authError {
        case .invalidConfiguration, .unconfigured:
            return .init(
                category: .serviceUnavailable,
                message: L(
                    "auth.error.unavailable",
                    defaultValue: "Sign in is temporarily unavailable."
                ),
                shouldPresentToast: true
            )
        case .invalidIdentityToken, .unexpectedAuthorizationCredential:
            return .init(
                category: .appleCredentials,
                message: L(
                    "auth.error.apple_credentials",
                    defaultValue: "Could not verify your Apple account. Try again."
                ),
                shouldPresentToast: true
            )
        case .notAuthenticated, .unauthorized:
            if operation == .appleSignIn {
                return .init(
                    category: .appleCredentials,
                    message: L(
                        "auth.error.apple_credentials",
                        defaultValue: "Could not verify your Apple account. Try again."
                    ),
                    shouldPresentToast: true
                )
            }
            return .init(
                category: .unauthorized,
                message: L(
                    "auth.error.session_expired",
                    defaultValue: "Your session expired. Sign in again."
                ),
                shouldPresentToast: true
            )
        case .forbidden(_, let message):
            return .init(
                category: .forbidden,
                message: resolvedBusinessMessage(
                    message,
                    fallback: L(
                        "auth.error.forbidden",
                        defaultValue: "This account cannot sign in here."
                    )
                ),
                shouldPresentToast: true
            )
        case .rateLimited:
            return .init(
                category: .rateLimited,
                message: L(
                    "auth.error.rate_limited",
                    defaultValue: "Too many attempts. Please wait a bit and try again."
                ),
                shouldPresentToast: true
            )
        case .server(let statusCode, _, _):
            if operation == .appleSignIn, statusCode == 503 {
                return .init(
                    category: .serverUnavailable,
                    message: L(
                        "auth.error.apple_service_unavailable",
                        defaultValue: "Apple sign-in service is temporarily unavailable. Try again later."
                    ),
                    shouldPresentToast: true
                )
            }
            return .init(
                category: .serverUnavailable,
                message: L(
                    "auth.error.server",
                    defaultValue: "Server error. Try again later."
                ),
                shouldPresentToast: true
            )
        case .backend(_, let message, _):
            return .init(
                category: .business,
                message: resolvedBusinessMessage(
                    message,
                    fallback: L(
                        "auth.error.generic",
                        defaultValue: "Could not complete sign in. Try again."
                    )
                ),
                shouldPresentToast: true
            )
        case .invalidResponse, .decodingFailed:
            return .init(
                category: .invalidResponse,
                message: L(
                    "auth.error.invalid_response",
                    defaultValue: "Auth response parse failed. Try again."
                ),
                shouldPresentToast: true
            )
        case .tokenPersistenceFailed:
            return .init(
                category: .tokenPersistence,
                message: L(
                    "auth.error.token_persistence",
                    defaultValue: "Token persistence failed. Signed in, but failed to save your session."
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
                message: L(
                    "auth.error.offline",
                    defaultValue: "No internet connection. Check your network and try again."
                ),
                shouldPresentToast: true
            )
        case .cancelled:
            return .init(category: .requestCancelled, message: nil, shouldPresentToast: false)
        case .tls:
            return .init(
                category: .tls,
                message: L(
                    "auth.error.tls",
                    defaultValue: "Secure connection failed. Check your network and try again."
                ),
                shouldPresentToast: true
            )
        case .network:
            return .init(
                category: .transport,
                message: L(
                    "auth.error.network",
                    defaultValue: "Network error. Try again."
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
                message: L(
                    "auth.error.post_login_bootstrap",
                    defaultValue: "Post-login bootstrap failed. Your session is active."
                ),
                shouldPresentToast: true
            )
        case .wrongSessionNamespace:
            return .init(
                category: .wrongSessionNamespace,
                message: L(
                    "auth.error.wrong_session_namespace",
                    defaultValue: "Signed in, but the session belongs to a different backend or region."
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
