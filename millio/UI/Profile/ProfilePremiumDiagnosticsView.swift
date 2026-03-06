import SwiftUI

struct ProfilePremiumDiagnosticsView: View {
    @Environment(AppState.self) private var appState

    private var diagnosticItems: [EntitlementDiagnosticItem] {
        EntitlementDiagnostics.items(for: appState)
    }

    private var isRussian: Bool {
        (appState.selectedLanguage.locale ?? Locale.current).identifier.hasPrefix("ru")
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
        .navigationTitle(isRussian ? "Диагностика Premium" : "Premium diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text(isRussian ? "Текущий доступ" : "Current access")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                HStack {
                    statusBadge(
                        title: accessSourceTitle,
                        tint: appState.isPro ? AppColors.brandPrimary : AppColors.textTertiary
                    )

                    if appState.hasDebugPremiumOverride {
                        statusBadge(title: isRussian ? "Debug override" : "Debug override", tint: AppColors.toggleOnGreen)
                    }

                    Spacer()
                }

                detailRow(title: isRussian ? "Эффективный premium" : "Effective premium", value: appState.isPro ? (isRussian ? "Вкл" : "On") : (isRussian ? "Выкл" : "Off"))
                detailRow(title: isRussian ? "Сохранённый статус" : "Stored status", value: subscriptionStatusTitle)
                detailRow(title: isRussian ? "Триал" : "Trial", value: appState.isTrialActive ? (isRussian ? "Активен" : "Active") : (isRussian ? "Неактивен" : "Inactive"))

                if let expirationDate = appState.subscriptionExpirationDate {
                    detailRow(
                        title: isRussian ? "Истекает" : "Expiration",
                        value: expirationDate.formatted(date: .abbreviated, time: .omitted)
                    )
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text(isRussian ? "Где premium меняет поведение" : "Where premium changes behavior")
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

                        Text("\(isRussian ? "Free" : "Free"): \(item.freeBehavior)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                        Text("\(isRussian ? "Premium" : "Premium"): \(item.premiumBehavior)")
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
            return isRussian ? "Free" : "Free"
        case .trial:
            return isRussian ? "Триал" : "Trial"
        case .subscription:
            return isRussian ? "Подписка" : "Subscription"
        case .debug:
            return isRussian ? "Debug premium" : "Debug premium"
        }
    }

    private var subscriptionStatusTitle: String {
        switch appState.subscriptionStatus {
        case .notSubscribed:
            return isRussian ? "Нет подписки" : "Not subscribed"
        case .trial:
            return isRussian ? "Триал" : "Trial"
        case .subscribed:
            return isRussian ? "Подписка активна" : "Subscribed"
        case .expired:
            return isRussian ? "Истекла" : "Expired"
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
