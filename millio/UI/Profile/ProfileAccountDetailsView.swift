import AuthenticationServices
import SwiftUI

struct ProfileAccountDetailsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState

    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let cardCornerRadius: CGFloat = 22
        static let sectionSpacing: CGFloat = 18
        static let primaryButtonHeight: CGFloat = 48
        static let secondaryButtonHeight: CGFloat = 46
        static let buttonCornerRadius: CGFloat = 14
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let title = String(localized: "profile.auth.account_details", defaultValue: "Account details", comment: "Account details screen title")
    private let connectedTitle = String(localized: "profile.auth.connected", defaultValue: "Connected with Apple ID", comment: "Connected state title")
    private let connectedSubtitle = String(localized: "profile.auth.connected.subtitle", defaultValue: "Your account is ready for sync and restore.", comment: "Connected state subtitle")
    private let logoutTitle = String(localized: "profile.auth.logout", defaultValue: "Logout", comment: "Logout button")
    private let emailMissingTitle = String(localized: "profile.auth.email_missing", defaultValue: "Email is not available", comment: "Fallback email text")
    private let guestTitle = String(localized: "profile.auth.guest.title", defaultValue: "Guest mode", comment: "Guest mode title")
    private let guestSubtitle = String(localized: "profile.auth.guest.subtitle", defaultValue: "You can use the app now and connect an Apple account later.", comment: "Guest mode subtitle")
    private let exitGuestTitle = String(localized: "profile.auth.exit_guest", defaultValue: "Exit guest mode", comment: "Exit guest mode button title")
    private let signedOutTitle = String(localized: "profile.auth.not_signed_in", defaultValue: "Not signed in", comment: "Signed-out auth state title")
    private let signedOutSubtitle = String(localized: "profile.auth.not_signed_in.subtitle", defaultValue: "Connect your Apple account to sync and restore access.", comment: "Signed-out auth state subtitle")
    private let nameTitle = String(localized: "profile.auth.name", defaultValue: "Name", comment: "Account detail field title for name")
    private let emailTitle = String(localized: "profile.auth.email", defaultValue: "Email", comment: "Account detail field title for email")
    private let lastLoginTitle = String(localized: "profile.auth.last_login", defaultValue: "Last login", comment: "Account detail field title for last login")

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: Layout.sectionSpacing) {
                    if authManager.isAuthenticated, let user = authManager.currentUser {
                        authenticatedContent(for: user)
                    } else if appState.isGuestModeEnabled {
                        guestContent
                    } else {
                        signedOutContent
                    }
                }
                .padding(.horizontal, Layout.horizontalInset)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func authenticatedContent(for user: AuthUser) -> some View {
        VStack(spacing: Layout.sectionSpacing) {
            heroCard(for: user)

            card {
                VStack(spacing: 0) {
                    detailsRow(title: nameTitle, value: ProfileDisplayNameResolver.userDisplayName(user) ?? SettingsManager.defaultProfileDisplayName)
                    divider()
                    detailsRow(title: emailTitle, value: user.email ?? emailMissingTitle)

                    if let lastLoginAt = user.lastLoginAt {
                        divider()
                        detailsRow(title: lastLoginTitle, value: Self.dateFormatter.string(from: lastLoginAt))
                    }
                }
            }

            Button(logoutTitle) {
                Task { await authManager.logout() }
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(Color.red.opacity(0.9))
            .buttonStyle(.plain)
            .disabled(authManager.isBusy)
        }
    }

    private var guestContent: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text(guestTitle)
                    .font(.system(size: 20, weight: .bold))
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
                    .frame(height: Layout.primaryButtonHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.buttonCornerRadius, style: .continuous))
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
                        .frame(height: Layout.secondaryButtonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.buttonCornerRadius, style: .continuous)
                                .fill(.white.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Layout.buttonCornerRadius, style: .continuous)
                                        .stroke(.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(authManager.isBusy)
                }
            }
        }
    }

    private var signedOutContent: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text(signedOutTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(signedOutSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detailsRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            Text(value)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func heroCard(for user: AuthUser) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 6) {
                Text(connectedTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text(ProfileDisplayNameResolver.userDisplayName(user) ?? SettingsManager.defaultProfileDisplayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)

                Text(connectedSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func divider() -> some View {
        FinancesRowDivider(leadingPadding: 0)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.8)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
    }
}
