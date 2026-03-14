import AuthenticationServices
import SwiftUI

struct ProfileAuthSection: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState

    private enum GuestAuthLayout {
        static let primaryButtonHeight: CGFloat = 48
        static let secondaryButtonHeight: CGFloat = 46
        static let buttonCornerRadius: CGFloat = 14
    }

    private let connectedTitle = String(localized: "profile.auth.connected", defaultValue: "Signed in with Apple", comment: "Compact connected state title in profile")
    private let emailMissingTitle = String(localized: "profile.auth.email_missing", defaultValue: "No email provided", comment: "Fallback email text")
    private let guestTitle = String(localized: "profile.auth.guest.title", defaultValue: "Guest Mode", comment: "Guest mode title")
    private let guestSubtitle = String(localized: "profile.auth.guest.subtitle", defaultValue: "Use Millio now and connect your Apple Account later.", comment: "Guest mode subtitle")
    private let exitGuestTitle = String(localized: "profile.auth.exit_guest", defaultValue: "Leave Guest Mode", comment: "Exit guest mode button title")
    private let detailsTitle = String(localized: "profile.auth.details", defaultValue: "View details", comment: "Account details row accessory title")
    private let notSignedInTitle = String(localized: "profile.auth.not_signed_in", defaultValue: "Not signed in", comment: "Signed-out auth state title")
    private let notSignedInSubtitle = String(localized: "profile.auth.not_signed_in.subtitle", defaultValue: "Sign in with Apple to enable account sync. iCloud backup works separately.", comment: "Signed-out auth state subtitle")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if authManager.isAuthenticated, let user = authManager.currentUser {
                authenticatedSummary(for: user)
            } else if appState.isGuestModeEnabled {
                guestContent
            } else {
                signedOutContent
            }
        }
    }

    // Keep the profile row compact; session details live on the dedicated screen.
    private func authenticatedSummary(for user: AuthUser) -> some View {
        NavigationLink {
            ProfileAccountDetailsView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.08))

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.brandPrimary)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(connectedTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        connectedBadge
                    }

                    if let displayName = ProfileDisplayNameResolver.userDisplayName(user) {
                        Text(displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }

                    Text(user.email ?? emailMissingTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.accountDetailsLink")
    }

    private var connectedBadge: some View {
        Text(detailsTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.profileValueAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.06))
            )
    }

    private var guestContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(guestTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(guestSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                SignInWithAppleButton(.continue) { request in
                    authManager.markAppleSignInStarted()
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await authManager.signIn(with: result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: GuestAuthLayout.primaryButtonHeight)
                .clipShape(RoundedRectangle(cornerRadius: GuestAuthLayout.buttonCornerRadius, style: .continuous))
                .disabled(authManager.isBusy)

                Button {
                    appState.isGuestModeEnabled = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.circle")
                            .font(.system(size: 15, weight: .semibold))

                        Text(exitGuestTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AppColors.textPrimary.opacity(authManager.isBusy ? 0.45 : 0.88))
                    .frame(maxWidth: .infinity)
                    .frame(height: GuestAuthLayout.secondaryButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: GuestAuthLayout.buttonCornerRadius, style: .continuous)
                            .fill(.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: GuestAuthLayout.buttonCornerRadius, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(authManager.isBusy)
            }
        }
    }

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notSignedInTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(notSignedInSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
