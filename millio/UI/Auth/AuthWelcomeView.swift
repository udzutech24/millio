import AuthenticationServices
import SwiftUI

struct AuthWelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    @ScaledMetric(relativeTo: .body) private var screenHorizontalPadding: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var screenBottomPadding: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var headerTopSpacer: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var headerToCardSpacer: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var sectionSpacing: CGFloat = 24

    @ScaledMetric(relativeTo: .body) private var cardCornerRadius: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var cardPaddingTop: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var cardPaddingHorizontal: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var cardPaddingBottom: CGFloat = 20

    @ScaledMetric(relativeTo: .body) private var pillCornerRadius: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var pillVerticalPadding: CGFloat = 10

    @ScaledMetric(relativeTo: .largeTitle) private var heroTitleSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title3) private var brandTitleSize: CGFloat = 20

    @ScaledMetric(relativeTo: .body) private var primaryButtonHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var secondaryButtonHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var buttonCornerRadius: CGFloat = 14

    private enum L10n {
        static let badgePrivateAccess: LocalizedStringKey = "auth.welcome.badge.private_access"
        static let brand: LocalizedStringKey = "auth.welcome.brand"
        static let title: LocalizedStringKey = "auth.welcome.title"
        static let subtitle: LocalizedStringKey = "auth.welcome.subtitle"
        static let continueWithoutAccount: LocalizedStringKey = "auth.welcome.cta.continue_without_account"
        static let featureAppleSignIn: LocalizedStringKey = "auth.welcome.feature.apple_sign_in"
        static let featurePrivateSession: LocalizedStringKey = "auth.welcome.feature.private_session"
        static let featureGuestAccess: LocalizedStringKey = "auth.welcome.feature.guest_access"
    }

    private let featureItems: [(icon: String, title: LocalizedStringKey)] = [
        ("person.crop.circle.badge.checkmark", L10n.featureAppleSignIn),
        ("lock.fill", L10n.featurePrivateSession),
        ("sparkles", L10n.featureGuestAccess)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GradientBackground(
                    topGradientColor: "153A7A",
                    topGradientFadeColor: "07111B",
                    bottomGradientColor: "6B93FF",
                    bottomGradientFadeColor: "04070D"
                )

                Circle()
                    .fill(Color(hex: "6B93FF").opacity(0.24))
                    .frame(width: 340, height: 340)
                    .blur(radius: 42)
                    .offset(x: -110, y: -280)

                Circle()
                    .fill(Color(hex: "C8A56A").opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 48)
                    .offset(x: 120, y: -110)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        Spacer(minLength: headerTopSpacer)

                        header

                        Spacer(minLength: headerToCardSpacer)

                        FinancesGlassCard(
                            accentColor: AppColors.brandPrimary,
                            cornerRadius: cardCornerRadius,
                            contentPadding: EdgeInsets(
                                top: cardPaddingTop,
                                leading: cardPaddingHorizontal,
                                bottom: cardPaddingBottom,
                                trailing: cardPaddingHorizontal
                            )
                        ) {
                            VStack(alignment: .leading, spacing: sectionSpacing) {
                                hero
                                featureList
                                actionBlock
                            }
                        }
                    }
                    .frame(
                        minHeight: proxy.size.height - max(proxy.safeAreaInsets.bottom, 18),
                        alignment: .bottom
                    )
                }
                .padding(.horizontal, screenHorizontalPadding)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, screenBottomPadding))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.badgePrivateAccess)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.6)
            }
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )

            Text(L10n.brand)
                .font(.system(size: brandTitleSize, weight: .semibold, design: .default))
                .foregroundStyle(Color.white.opacity(0.88))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.title)
                .font(.system(size: heroTitleSize, weight: .semibold, design: .default))
                .foregroundStyle(Color.white)
                .kerning(-0.4)
                .lineLimit(3)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.subtitle)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(featureItems, id: \.icon) { item in
                premiumPill(icon: item.icon, title: item.title)
            }
        }
    }

    private func premiumPill(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .frame(width: 18)
            Text(title)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, pillVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var actionBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await authManager.signIn(with: result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: primaryButtonHeight)
            .clipShape(RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous))
            .disabled(authManager.isBusy)

            Button {
                appState.isGuestModeEnabled = true
            } label: {
                Text(L10n.continueWithoutAccount)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .frame(height: secondaryButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(authManager.isBusy)
        }
    }
}
