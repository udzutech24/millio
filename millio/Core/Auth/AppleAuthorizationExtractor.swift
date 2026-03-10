@preconcurrency import AuthenticationServices
import Foundation

struct AppleAuthorizationPayload: Equatable, Sendable {
    let identityToken: String
    let email: String?
    let firstName: String?
    let lastName: String?
}

protocol AppleAuthorizationExtracting: Sendable {
    func extract(from authorization: Result<ASAuthorization, Error>) throws -> AppleAuthorizationPayload
}

struct AppleAuthorizationExtractor: AppleAuthorizationExtracting {
    func extract(from authorization: Result<ASAuthorization, Error>) throws -> AppleAuthorizationPayload {
        let resolvedAuthorization = try authorization.get()
        guard let credential = resolvedAuthorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthServiceError.unexpectedAuthorizationCredential
        }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthServiceError.invalidIdentityToken
        }

        return AppleAuthorizationPayload(
            identityToken: identityToken,
            email: credential.email,
            firstName: credential.fullName?.givenName,
            lastName: credential.fullName?.familyName
        )
    }
}
