import AuthenticationServices
import SwiftUI

struct ProfileAuthSection: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let signedInTitle = String(localized: "profile.auth.signed_in.title", defaultValue: "Account", comment: "Signed-in state title")
    private let refreshTitle = String(localized: "profile.auth.refresh", defaultValue: "Refresh profile", comment: "Refresh profile button")
    private let logoutTitle = String(localized: "profile.auth.logout", defaultValue: "Logout", comment: "Logout button")
    private let accessTokenExpiresTitle = String(localized: "profile.auth.access_expires", defaultValue: "Access token expires", comment: "Access token expiration prefix")
    private let emailMissingTitle = String(localized: "profile.auth.email_missing", defaultValue: "Email is not available", comment: "Fallback email text")
    private let guestTitle = String(localized: "profile.auth.guest.title", defaultValue: "Guest mode", comment: "Guest mode title")
    private let guestSubtitle = String(localized: "profile.auth.guest.subtitle", defaultValue: "You can use the app now and connect an Apple account later.", comment: "Guest mode subtitle")
    private let exitGuestTitle = String(localized: "profile.auth.exit_guest", defaultValue: "Exit guest mode", comment: "Exit guest mode button title")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if authManager.isAuthenticated, let user = authManager.currentUser {
                authenticatedContent(for: user)
            } else if appState.isGuestModeEnabled {
                guestContent
            } else {
                Text("Not signed in")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var guestContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(guestTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(guestSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SignInWithAppleButton(.continue) { request in
                authManager.markAppleSignInStarted()
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await authManager.signIn(with: result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(authManager.isBusy)

            Button(exitGuestTitle) {
                appState.isGuestModeEnabled = false
            }
            .buttonStyle(.bordered)
            .disabled(authManager.isBusy)
        }
    }

    @ViewBuilder
    func authenticatedContent(for user: AuthUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(signedInTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(user.fullName ?? user.email ?? user.id)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text(user.email ?? emailMissingTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            if let expiresAt = authManager.accessTokenExpiresAt {
                Text("\(accessTokenExpiresTitle): \(Self.dateFormatter.string(from: expiresAt))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }

            HStack(spacing: 12) {
                Button(refreshTitle) {
                    Task { await authManager.reloadCurrentUser() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brandPrimary)
                .disabled(authManager.isBusy)

                Button(logoutTitle) {
                    Task { await authManager.logout() }
                }
                .buttonStyle(.bordered)
                .disabled(authManager.isBusy)
            }
        }
    }

    static let sectionHeaderTitle = String(localized: "profile.auth.section.title", defaultValue: "Account", comment: "Profile auth section title")
}
