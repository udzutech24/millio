import SwiftUI

struct ProfilePremiumDiagnosticsView: View {
    @Environment(AppState.self) private var appState

    private var diagnosticItems: [EntitlementDiagnosticItem] {
        EntitlementDiagnostics.items(for: appState)
    }

    private var locale: Locale {
        AppLocalization.currentAppLocale
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                        .padding(.top, 20)

                    diagnosticsCard
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("profile.premium.diagnostics.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("profile.premium.diagnostics.current_access"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                HStack {
                    statusBadge(
                        title: accessSourceTitle,
                        tint: appState.isPro ? AppColors.brandPrimary : AppColors.textTertiary
                    )

                    if appState.hasDebugPremiumOverride {
                        statusBadge(
                            title: AppLocalization.string("profile.premium.diagnostics.debug_override", locale: locale),
                            tint: AppColors.toggleOnGreen
                        )
                    }

                    Spacer()
                }

                detailRow(
                    title: AppLocalization.string("profile.premium.diagnostics.effective_premium", locale: locale),
                    value: appState.isPro
                    ? AppLocalization.string("profile.premium.diagnostics.on", locale: locale)
                    : AppLocalization.string("profile.premium.diagnostics.off", locale: locale)
                )
                detailRow(
                    title: AppLocalization.string("profile.premium.diagnostics.stored_status", locale: locale),
                    value: subscriptionStatusTitle
                )
                detailRow(
                    title: AppLocalization.string("profile.premium.diagnostics.trial", locale: locale),
                    value: appState.isTrialActive
                    ? AppLocalization.string("profile.premium.diagnostics.active", locale: locale)
                    : AppLocalization.string("profile.premium.diagnostics.inactive", locale: locale)
                )
                detailRow(
                    title: AppLocalization.string("profile.premium.diagnostics.trial_disabled", locale: locale),
                    value: appState.hasTrialDisabledOverride
                    ? AppLocalization.string("profile.premium.diagnostics.yes", locale: locale)
                    : AppLocalization.string("profile.premium.diagnostics.no", locale: locale)
                )

                if let expirationDate = appState.subscriptionExpirationDate {
                    detailRow(
                        title: AppLocalization.string("profile.premium.diagnostics.expiration", locale: locale),
                        value: expirationDate.formatted(date: .abbreviated, time: .omitted)
                    )
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("profile.premium.diagnostics.behavior"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                ForEach(diagnosticItems) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(item.location)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textTertiary)
                            }

                            Spacer()

                            statusBadge(
                                title: item.currentState,
                                tint: item.isPremiumActive ? AppColors.toggleOnGreen : AppColors.textTertiary
                            )
                        }

                        Text("\(AppLocalization.string("profile.premium.diagnostics.free", locale: locale)): \(item.freeBehavior)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                        Text("\(AppLocalization.string("profile.premium.diagnostics.pro", locale: locale)): \(item.premiumBehavior)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if item.id != diagnosticItems.last?.id {
                        Divider()
                            .overlay(AppColors.textPrimary.opacity(0.08))
                    }
                }
            }
        }
    }

    private var accessSourceTitle: String {
        switch appState.subscriptionAccessSource {
        case .free:
            return AppLocalization.string("profile.premium.diagnostics.access.free", locale: locale)
        case .trial:
            return AppLocalization.string("profile.premium.diagnostics.access.trial", locale: locale)
        case .subscription:
            return AppLocalization.string("profile.premium.diagnostics.access.subscription", locale: locale)
        case .debug:
            return AppLocalization.string("profile.premium.diagnostics.access.debug", locale: locale)
        }
    }

    private var subscriptionStatusTitle: String {
        switch appState.subscriptionStatus {
        case .notSubscribed:
            return AppLocalization.string("profile.premium.diagnostics.status.not_subscribed", locale: locale)
        case .trial:
            return AppLocalization.string("profile.premium.diagnostics.status.trial", locale: locale)
        case .subscribed:
            return AppLocalization.string("profile.premium.diagnostics.status.subscribed", locale: locale)
        case .expired:
            return AppLocalization.string("profile.premium.diagnostics.status.expired", locale: locale)
        }
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppColors.profileCardBackgroundGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.profileCardStrokeGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .padding(.horizontal, 20)
    }
}

#Preview {
    NavigationStack {
        ProfilePremiumDiagnosticsView()
            .environment(AppState())
    }
}
