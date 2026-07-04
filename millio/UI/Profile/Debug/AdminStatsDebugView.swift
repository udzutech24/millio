#if DEBUG
import SwiftUI
import SwiftData

struct AdminStatsDebugView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(\.diContainer) private var diContainer

    @State private var viewModel: AdminStatsDebugViewModel?
    @State private var bootstrapErrorMessage: String?
    @State private var seedResultMessage: String?
    @State private var showSeedResult = false

    private var locale: Locale {
        AppLocalization.currentAppLocale
    }

    var body: some View {
        ZStack {
            GradientBackground()

            Group {
                if let viewModel {
                    AdminStatsDebugContent(
                        viewModel: viewModel,
                        locale: locale,
                        onRefreshUser: {
                            await authManager.reloadCurrentUser()
                        }
                    )
                } else if let bootstrapErrorMessage {
                    stateCard(
                        title: AppLocalization.string("profile.admin_stats.error.title", locale: locale, fallback: "Could not load admin stats"),
                        message: bootstrapErrorMessage,
                        systemImage: "exclamationmark.triangle"
                    )
                } else {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                }
            }
        }
        .navigationTitle("profile.admin_stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let viewModel {
                    Button {
                        Task {
                            await viewModel.refresh()
                            await authManager.reloadCurrentUser()
                        }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .tint(AppColors.textPrimary)
                }
            }
            // Полигон нового ядра счетов (Фаза 1a-ui, П4 в плане) — скрытая DEBUG-кнопка,
            // доступна только с этого уже DEBUG+admin-гейтованного экрана (см. ProfileView.shouldDisplayMenuItem).
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    seedAccountsCoreDemo()
                } label: {
                    Image(systemName: "shippingbox.fill")
                }
                .tint(AppColors.textPrimary)
                .accessibilityIdentifier("profile.adminStats.seedAccountsCoreButton")
            }
        }
        .alert(
            AppLocalization.string("accounts_core.debug.seed_confirm.title", locale: locale),
            isPresented: $showSeedResult
        ) {
            Button(AppLocalization.string("accounts_core.detail.sheet.cancel", locale: locale)) {}
        } message: {
            Text(seedResultMessage ?? "")
        }
        .task {
            guard viewModel == nil else { return }
            AppLogger.log(.debug, category: "AdminStats", "Admin stats screen opened")
            await authManager.reloadCurrentUser()
            guard let diContainer else {
                let message = "Debug dependencies are not available in this app session."
                AppLogger.log(.error, category: "AdminStats", "Admin stats bootstrap failed: missing DI container")
                bootstrapErrorMessage = message
                return
            }

            AppLogger.log(.debug, category: "AdminStats", "Admin stats view model created")
            let loadedViewModel = AdminStatsDebugViewModel(
                repository: diContainer.apiClientFactory.makeAdminStatsRepository(
                    authService: diContainer.authService
                )
            )
            bootstrapErrorMessage = nil
            viewModel = loadedViewModel
            await loadedViewModel.loadIfNeeded()
        }
    }

    /// Прогоняет `AccountsCoreSeeder.seedDemoPortfolio` (Фаза 1a-ui, П4) — единственный способ
    /// вызвать полигон из UI, без нового пункта меню Profile (минимально-инвазивно, см. бриф).
    private func seedAccountsCoreDemo() {
        guard let diContainer else {
            seedResultMessage = "Debug dependencies are not available in this app session."
            showSeedResult = true
            return
        }
        let context = diContainer.modelContainer.mainContext
        do {
            let didSeed = try AccountsCoreSeeder.seedDemoPortfolio(context: context)
            seedResultMessage = didSeed
                ? AppLocalization.string("accounts_core.debug.seed_success", locale: locale)
                : AppLocalization.string("accounts_core.debug.seed_already_done", locale: locale)
        } catch {
            seedResultMessage = error.localizedDescription
        }
        showSeedResult = true
    }

    private var loadingCard: some View {
        card {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(AppColors.textPrimary)

                Text(AppLocalization.string("profile.admin_stats.loading", locale: locale, fallback: "Loading admin statistics"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryCard(_ snapshot: AdminStatsSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.string("profile.admin_stats.summary.title", locale: locale, fallback: "Overview"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.total_users", locale: locale, fallback: "Total users"),
                        value: snapshot.totalUsers
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.last_7_days", locale: locale, fallback: "Active in last 7 days"),
                        value: snapshot.usersLoggedInLast7Days
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.last_30_days", locale: locale, fallback: "Active in last 30 days"),
                        value: snapshot.usersLoggedInLast30Days
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.watchlist_users", locale: locale, fallback: "Users with watchlist"),
                        value: snapshot.usersWithWatchlist
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.watchlist_items", locale: locale, fallback: "Watchlist items"),
                        value: snapshot.totalWatchlistItems
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.symbol_limit", locale: locale, fallback: "Top symbols limit"),
                        value: snapshot.requestedSymbolsLimit
                    )
                }

                HStack(spacing: 8) {
                    Text(AppLocalization.string("profile.admin_stats.generated_at", locale: locale, fallback: "Last updated"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()

                    Text(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }

    private func symbolsCard(_ snapshot: AdminStatsSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.string("profile.admin_stats.symbols.title", locale: locale, fallback: "Top symbols"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                if snapshot.topSymbols.isEmpty {
                    Text(AppLocalization.string("profile.admin_stats.symbols.empty", locale: locale, fallback: "No popular symbols yet"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                } else {
                    ForEach(Array(snapshot.topSymbols.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(width: 18, alignment: .leading)

                            Text(item.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()

                            Text("\(item.usersCount)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        if index < snapshot.topSymbols.count - 1 {
                            FinancesRowDivider()
                        }
                    }
                }
            }
        }
    }

    private func stateCard(title: String, message: String, systemImage: String) -> some View {
        card {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        await viewModel?.refresh()
                        await authManager.reloadCurrentUser()
                    }
                } label: {
                    Text(AppLocalization.string("profile.admin_stats.refresh", locale: locale, fallback: "Refresh"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColors.accentDarkBlue.opacity(0.36))
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func metricTile(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(value)")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.accentDarkBlue.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
                )
        )
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

private struct AdminStatsDebugContent: View {
    @ObservedObject var viewModel: AdminStatsDebugViewModel
    let locale: Locale
    let onRefreshUser: @MainActor () async -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch viewModel.screenState {
                case .idle, .loading:
                    loadingCard
                case .success(let snapshot):
                    summaryCard(snapshot)
                    symbolsCard(snapshot)
                case .empty:
                    stateCard(
                        title: AppLocalization.string("profile.admin_stats.empty.title", locale: locale, fallback: "No admin stats yet"),
                        message: AppLocalization.string("profile.admin_stats.empty.message", locale: locale, fallback: "The backend returned an empty snapshot for this account."),
                        systemImage: "tray"
                    )
                case .unauthorized(let message):
                    stateCard(
                        title: AppLocalization.string("profile.admin_stats.unauthorized.title", locale: locale, fallback: "Authorization required"),
                        message: message,
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                case .forbidden(let message):
                    stateCard(
                        title: AppLocalization.string("profile.admin_stats.forbidden.title", locale: locale, fallback: "ADMIN access required"),
                        message: message,
                        systemImage: "lock.shield"
                    )
                case .networkError(let message):
                    stateCard(
                        title: AppLocalization.string("profile.admin_stats.network_error.title", locale: locale, fallback: "Network error"),
                        message: message,
                        systemImage: "wifi.exclamationmark"
                    )
                case .error(let message):
                    stateCard(
                        title: AppLocalization.string("profile.admin_stats.error.title", locale: locale, fallback: "Could not load admin stats"),
                        message: message,
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .padding(.vertical, 20)
        }
        .refreshable {
            await viewModel.refresh()
            await onRefreshUser()
        }
    }

    private var loadingCard: some View {
        card {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(AppColors.textPrimary)

                Text(AppLocalization.string("profile.admin_stats.loading", locale: locale, fallback: "Loading admin statistics"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryCard(_ snapshot: AdminStatsSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.string("profile.admin_stats.summary.title", locale: locale, fallback: "Overview"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.total_users", locale: locale, fallback: "Total users"),
                        value: snapshot.totalUsers
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.last_7_days", locale: locale, fallback: "Active in last 7 days"),
                        value: snapshot.usersLoggedInLast7Days
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.last_30_days", locale: locale, fallback: "Active in last 30 days"),
                        value: snapshot.usersLoggedInLast30Days
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.watchlist_users", locale: locale, fallback: "Users with watchlist"),
                        value: snapshot.usersWithWatchlist
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.watchlist_items", locale: locale, fallback: "Watchlist items"),
                        value: snapshot.totalWatchlistItems
                    )
                    metricTile(
                        title: AppLocalization.string("profile.admin_stats.symbol_limit", locale: locale, fallback: "Top symbols limit"),
                        value: snapshot.requestedSymbolsLimit
                    )
                }

                HStack(spacing: 8) {
                    Text(AppLocalization.string("profile.admin_stats.generated_at", locale: locale, fallback: "Last updated"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()

                    Text(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }

    private func symbolsCard(_ snapshot: AdminStatsSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.string("profile.admin_stats.symbols.title", locale: locale, fallback: "Top symbols"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                if snapshot.topSymbols.isEmpty {
                    Text(AppLocalization.string("profile.admin_stats.symbols.empty", locale: locale, fallback: "No popular symbols yet"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)

                    Text(
                        AppLocalization.string(
                            "profile.admin_stats.symbols.backend_empty",
                            locale: locale,
                            fallback: "Top symbols returned 0 items from backend"
                        )
                    )
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(Array(snapshot.topSymbols.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(width: 18, alignment: .leading)

                            Text(item.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()

                            Text("\(item.usersCount)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        if index < snapshot.topSymbols.count - 1 {
                            FinancesRowDivider()
                        }
                    }
                }
            }
        }
    }

    private func stateCard(title: String, message: String, systemImage: String) -> some View {
        card {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        await viewModel.refresh()
                        await onRefreshUser()
                    }
                } label: {
                    Text(AppLocalization.string("profile.admin_stats.refresh", locale: locale, fallback: "Refresh"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColors.accentDarkBlue.opacity(0.36))
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func metricTile(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(value)")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.accentDarkBlue.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
                )
        )
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

#endif
