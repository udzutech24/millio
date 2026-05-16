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

    @ScaledMetric(relativeTo: .largeTitle) private var heroTitleSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title3) private var brandTitleSize: CGFloat = 20

    @ScaledMetric(relativeTo: .body) private var primaryButtonHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var secondaryButtonHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var buttonCornerRadius: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var badgeHorizontalPadding: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var badgeVerticalPadding: CGFloat = 10
    @ScaledMetric(relativeTo: .caption) private var badgeIconSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var badgeTracking: CGFloat = 1.6

    private enum L10n {
        static let badgePrivateAccess: LocalizedStringKey = "auth.welcome.badge.private_access"
        static let brand: LocalizedStringKey = "auth.welcome.brand"
        static let title: LocalizedStringKey = "auth.welcome.title"
        static let subtitle: LocalizedStringKey = "auth.welcome.subtitle"
        static let continueWithoutAccount: LocalizedStringKey = "auth.welcome.cta.continue_without_account"
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = AuthWelcomeLayoutPolicy.metrics(containerSize: proxy.size)

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

                VStack(alignment: .leading, spacing: scaled(headerToCardSpacer, by: metrics.headerToCardSpacing / 12)) {
                    Spacer(minLength: scaled(headerTopSpacer, by: metrics.topSpacerMinLength / 36))

                    header(metrics: metrics)

                    FinancesGlassCard(
                        accentColor: AppColors.brandPrimary,
                        cornerRadius: scaled(cardCornerRadius, by: metrics.cardCornerRadius / 28),
                        contentPadding: EdgeInsets(
                            top: scaled(cardPaddingTop, by: metrics.cardPaddingTop / 24),
                            leading: scaled(cardPaddingHorizontal, by: metrics.cardPaddingHorizontal / 22),
                            bottom: scaled(cardPaddingBottom, by: metrics.cardPaddingBottom / 20),
                            trailing: scaled(cardPaddingHorizontal, by: metrics.cardPaddingHorizontal / 22)
                        )
                    ) {
                        VStack(alignment: .leading, spacing: scaled(sectionSpacing, by: metrics.sectionSpacing / 24)) {
                            hero(metrics: metrics)
                            actionBlock(metrics: metrics)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, scaled(screenHorizontalPadding, by: metrics.horizontalPadding / 20))
                .padding(.top, proxy.safeAreaInsets.top + scaled(12, by: metrics.topPadding / 12))
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, scaled(screenBottomPadding, by: metrics.bottomPadding / 18)))
            }
        }
    }

    private func header(metrics: AuthWelcomeLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: scaled(14, by: metrics.headerSpacing / 14)) {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: scaled(badgeIconSize, by: metrics.badgeIconSize / 14), weight: .semibold))
                Text(L10n.badgePrivateAccess)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(scaled(badgeTracking, by: metrics.badgeTracking / 1.6))
            }
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, scaled(badgeHorizontalPadding, by: metrics.badgeHorizontalPadding / 14))
            .padding(.vertical, scaled(badgeVerticalPadding, by: metrics.badgeVerticalPadding / 10))
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )

            Text(L10n.brand)
                .font(.system(size: scaled(brandTitleSize, by: metrics.brandTitleScale), weight: .semibold, design: .default))
                .foregroundStyle(Color.white.opacity(0.88))
        }
    }

    private func hero(metrics: AuthWelcomeLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: scaled(14, by: metrics.heroSpacing / 14)) {
            Text(L10n.title)
                .font(.system(size: scaled(heroTitleSize, by: metrics.heroTitleScale), weight: .semibold, design: .default))
                .foregroundStyle(Color.white)
                .kerning(-0.4)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.subtitle)
                .font(.system(size: scaled(17, by: metrics.subtitleScale)))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionBlock(metrics: AuthWelcomeLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: scaled(12, by: metrics.actionSpacing / 12)) {
            SignInWithAppleButton(.continue) { request in
                authManager.markAppleSignInStarted()
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await authManager.signIn(with: result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: scaled(primaryButtonHeight, by: metrics.primaryButtonHeight / 52))
            .clipShape(RoundedRectangle(cornerRadius: scaled(buttonCornerRadius, by: metrics.buttonCornerRadius / 14), style: .continuous))
            .disabled(authManager.isBusy)

            Button {
                appState.isGuestModeEnabled = true
            } label: {
                Text(L10n.continueWithoutAccount)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .frame(height: scaled(secondaryButtonHeight, by: metrics.secondaryButtonHeight / 50))
                    .background(
                        RoundedRectangle(cornerRadius: scaled(buttonCornerRadius, by: metrics.buttonCornerRadius / 14), style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: scaled(buttonCornerRadius, by: metrics.buttonCornerRadius / 14), style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(authManager.isBusy)

            if let errorMessage = authManager.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.millioCallout)
                    .foregroundStyle(Color.red.opacity(0.92))
            }
        }
    }

    private func scaled(_ base: CGFloat, by multiplier: CGFloat) -> CGFloat {
        base * multiplier
    }
}
