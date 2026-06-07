//
//  FinancesView.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finances Tab Enum

private func financesLocalized(_ key: String) -> String {
    FinancesL10n.tr(key)
}

enum FinancesInternalTab: String {
    case main = "main"
    case dynamics = "dynamics"
}

@MainActor
enum FinancesDeepLinkHandler {
    static func openAddCardIfRequested(appState: AppState, viewModel: FinanceViewModel?) {
        guard appState.pendingOpenFinanceAddCard, let viewModel else { return }
        appState.pendingOpenFinanceAddCard = false
        viewModel.handle(.showAddAccountSheet(nil))
    }
}

struct FinancesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel: FinanceViewModel?
    @State private var showQuickNavigationPopover: Bool = false
    private let currentRoute: AppRoute = .finances
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                FinancesContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                let createdViewModel = FinanceViewModel(modelContext: modelContext)
                viewModel = createdViewModel
                FinancesDeepLinkHandler.openAddCardIfRequested(
                    appState: appState,
                    viewModel: createdViewModel
                )
            } else {
                FinancesDeepLinkHandler.openAddCardIfRequested(
                    appState: appState,
                    viewModel: viewModel
                )
            }
        }
        .onChange(of: appState.pendingOpenFinanceAddCard) { _, _ in
            FinancesDeepLinkHandler.openAddCardIfRequested(appState: appState, viewModel: viewModel)
        }
        .onChange(of: appState.primaryCurrencyCode) { oldValue, newValue in
            viewModel?.handle(.syncPrimaryCurrencyChange(old: oldValue, new: newValue))
        }
        .onDisappear {
            viewModel?.handle(.setDisplayCurrency(appState.primaryCurrencyCode))
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .interactiveBackSwipe()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    toolbarButtonLabel(systemName: "chevron.left", weight: .semibold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(financesLocalized("finances.common.back"))
                
                Button {
                    showQuickNavigationPopover.toggle()
                } label: {
                    toolbarButtonLabel(systemName: "square.grid.2x2", weight: .regular)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(financesLocalized("finances.common.quick_navigation"))
                .popover(isPresented: $showQuickNavigationPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    MiniAppQuickNavigationPopover(
                        destinations: MiniAppNavigation.destinations(excluding: currentRoute)
                    ) { destination in
                        showQuickNavigationPopover = false
                        MiniAppNavigation.navigate(to: destination.route, from: currentRoute, router: router)
                    }
                    .presentationCompactAdaptation(.popover)
                }
            }

            }
    }

    private func toolbarButtonLabel(systemName: String, weight: Font.Weight) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: weight))
            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
            .frame(width: 28, height: 28)
    }
}

// MARK: - Internal Content View

private struct FinancesContentViewInternal: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab: FinancesInternalTab = .main

    var body: some View {
        TabView(selection: $selectedTab) {
            // Вкладка 1: Основной экран
            FinancesMainTabView(
                viewModel: viewModel,
                selectedTab: $selectedTab
            )
                .tabItem {
                    financesTabItemLabel(
                        titleKey: "finances.main.title",
                        imageName: "credit-card"
                    )
                }
                .tag(FinancesInternalTab.main)
            
            // Вкладка 2: Динамика
            FinanceDynamicsTabView(financeViewModel: viewModel)
                .tabItem {
                    financesTabItemLabel(
                        titleKey: "finances.dynamics.title",
                        imageName: "trending-up"
                    )
                }
                .tag(FinancesInternalTab.dynamics)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color.black.opacity(0.52), for: .tabBar)
    }

    private func financesTabItemLabel(titleKey: LocalizedStringKey, imageName: String) -> some View {
        Label {
            Text(titleKey)
        } icon: {
            Image(imageName)
                .renderingMode(.template)
        }
    }
}

struct FinancesSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FinanceViewModel
    @Binding var accountSortMode: AccountSortMode
    let onOpenSavingsGoal: () -> Void
    let onOpenMassTickerImport: () -> Void

    private var archivedAccounts: [ArchivedFinanceAccountRow] {
        viewModel.archivedAccountRows()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 12) {
                    Button {
                        onOpenMassTickerImport()
                    } label: {
                        settingsRow(
                            title: financesLocalized("finances.settings.mass_import.title"),
                            subtitle: financesLocalized("finances.settings.mass_import.subtitle"),
                            icon: "text.insert"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onOpenSavingsGoal()
                    } label: {
                        settingsRow(
                            title: financesLocalized("finances.settings.savings_goal.title"),
                            subtitle: financesLocalized("finances.settings.savings_goal.subtitle"),
                            icon: "target"
                        )
                    }
                    .buttonStyle(.plain)

                    if !archivedAccounts.isEmpty {
                        NavigationLink {
                            ArchivedFinanceAccountsView(
                                viewModel: viewModel
                            )
                        } label: {
                            settingsRow(
                                title: financesLocalized("finances.settings.archived_accounts.title"),
                                subtitle: financesLocalized("finances.settings.archived_accounts.subtitle"),
                                icon: "archivebox.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        AccountSortPickerView(sortMode: $accountSortMode)
                    } label: {
                        settingsRow(
                            title: financesLocalized("finances.settings.sort.title"),
                            subtitle: accountSortMode.title,
                            icon: "arrow.up.arrow.down"
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .navigationTitle(financesLocalized("finances.settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func settingsRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        )
    }
}

private struct ArchivedFinanceAccountsView: View {
    @ObservedObject var viewModel: FinanceViewModel

    private var accounts: [ArchivedFinanceAccountRow] {
        viewModel.archivedAccountRows()
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 10) {
                    Text(financesLocalized("finances.settings.archived_accounts.notice"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                    ForEach(accounts) { account in
                        archivedAccountRow(account)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(financesLocalized("finances.settings.archived_accounts.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func archivedAccountRow(_ account: ArchivedFinanceAccountRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: account.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(account.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(archivedSubtitle(for: account))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                Text(amountText(for: account))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Button {
                    viewModel.restoreArchivedAccount(account)
                } label: {
                    Text(financesLocalized("finances.settings.archived_accounts.restore"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        )
    }

    private func archivedSubtitle(for account: ArchivedFinanceAccountRow) -> String {
        let date = account.archivedAt.formatted(date: .abbreviated, time: .omitted)
        if let groupName = account.groupName, !groupName.isEmpty {
            return FinancesL10n.format("finances.settings.archived_accounts.subtitle_with_group", groupName, date)
        }
        return FinancesL10n.format("finances.settings.archived_accounts.subtitle_without_group", date)
    }

    private func amountText(for account: ArchivedFinanceAccountRow) -> String {
        let symbol = MonetaCurrency(rawValue: account.currency)?.symbol ?? account.currency
        return FinanceAmountText.withCurrency(value: account.amount, currencySymbol: symbol, isHidden: false)
    }
}

// MARK: - Account Sort Picker

private struct AccountSortPickerView: View {
    @Binding var sortMode: AccountSortMode

    var body: some View {
        ZStack {
            GradientBackground()
            VStack(spacing: 10) {
                ForEach(AccountSortMode.allCases, id: \.rawValue) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())

                            Text(mode.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if sortMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.incomeGradient.first ?? .green)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(sortMode == mode ? 0.09 : 0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(sortMode == mode ? 0.3 : 0.15), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .navigationTitle(financesLocalized("finances.settings.sort.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let schema = AppSchema.create()
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])

    FinancesView()
        .modelContainer(container)
        .environment(AppState())
}

// MARK: - Finances Main Tab View

struct FinancesMainTabView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Binding var selectedTab: FinancesInternalTab
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    var onNavigateToDynamics: (() -> Void)? = nil
    @State private var draggedGroupID: String?
    @State private var isEmptyIntroHidden: Bool = FinancesEmptyStateIntroPrefs().isHidden()
    @State private var showFinanceSettingsSheet = false
    @State private var showMassTickerImportSheet = false
    // Наблюдает за изменениями балансов через SwiftData — гарантирует перерисовку при изменении balance/amount
    @Query private var _allCards: [Card]

    // Хэш суммы балансов всех карт — меняется при любом изменении balance,
    // что гарантирует onChange-срабатывание через SwiftData-нотификацию
    private var cardBalanceHash: Int {
        _allCards.reduce(0) { acc, card in
            acc ^ card.balance.hashValue ^ card.cardUniqueID.hashValue
        }
    }

    var body: some View {
        mainContent
            .modifier(SheetsModifier(viewModel: viewModel))
            .sheet(isPresented: $showFinanceSettingsSheet) {
                FinancesSettingsSheet(
                    viewModel: viewModel,
                    accountSortMode: Binding(
                        get: { viewModel.state.accountSortMode },
                        set: { viewModel.handle(.setAccountSortMode($0)) }
                    ),
                    onOpenSavingsGoal: {
                        showFinanceSettingsSheet = false
                        viewModel.handle(.showSavingsGoalSheet)
                    },
                    onOpenMassTickerImport: {
                        showFinanceSettingsSheet = false
                        showMassTickerImportSheet = true
                    }
                )
            }
            .sheet(isPresented: $showMassTickerImportSheet) {
                StockBulkImportSheet(
                    financeViewModel: viewModel,
                    modelContext: modelContext,
                    marketDataClient: viewModel.marketDataClient
                )
            }
            .onAppear {
                isEmptyIntroHidden = FinancesEmptyStateIntroPrefs().isHidden()
            }
            .onChange(of: cardBalanceHash) { _, _ in
                viewModel.handle(.loadAccounts)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                let lastRefresh = viewModel.state.lastRefreshedAt ?? .distantPast
                guard Date().timeIntervalSince(lastRefresh) > 15 * 60 else { return }
                Task { await viewModel.refreshAll() }
            }
    }

    private var mainContent: some View {
        ZStack {
            GradientBackground()

            let visibleGroups = viewModel.visibleGroupsForList()
            let showsAddFAB = FinancesMainLayoutPolicy.showsAddFAB(visibleGroupsCount: visibleGroups.count)

            GeometryReader { proxy in
                let topInset = proxy.safeAreaInsets.top
                ScrollView {
                    VStack(spacing: 0) {
                        overviewUnifiedModule(hasSnapshot: !visibleGroups.isEmpty, topInset: topInset)

                        LazyVStack(spacing: FinancesMainLayoutPolicy.sectionSpacing) {
                            groupsListSection(visibleGroups)
                        }
                        .padding(.horizontal, FinancesMainLayoutPolicy.horizontalPadding)
                        .padding(.top, FinancesMainLayoutPolicy.sectionSpacing)
                        .padding(.bottom, FinancesMainLayoutPolicy.scrollContentBottomPadding(showsAddFAB: showsAddFAB))
                    }
                }
                .refreshable {
                    await viewModel.refreshAll()
                }
                .ignoresSafeArea(edges: .top)
            }

            if showsAddFAB {
                addFloatingButton
            }

            VStack {
                Spacer()
                if let message = viewModel.state.refreshIssueMessage {
                    ToastView(
                        message: message,
                        isPresented: Binding(
                            get: { viewModel.state.showRefreshIssue },
                            set: { isPresented in
                                if isPresented {
                                    viewModel.state.showRefreshIssue = true
                                } else {
                                    viewModel.dismissRefreshIssue()
                                }
                            }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Unified Hero + Overview Module

    private func overviewUnifiedModule(hasSnapshot: Bool, topInset: CGFloat = 0) -> some View {
        let r = FinancesMainLayoutPolicy.heroCornerRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: r,
            bottomTrailingRadius: r, topTrailingRadius: 0,
            style: .continuous
        )
        return VStack(alignment: .leading, spacing: 0) {
            totalAmountSection

            if hasSnapshot {
                FinanceOverviewCardView(
                    financeViewModel: viewModel,
                    chrome: .embedded
                )
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape
                .fill(FinanceScreenChrome.elevatedSurfaceFillGradient)
                .overlay {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [(AppColors.financesGradient.first ?? .cyan).opacity(0.10), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(0.7)
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill((AppColors.financesGradient.first ?? .cyan).opacity(0.12))
                        .blur(radius: 46)
                        .frame(width: 180, height: 180)
                        .offset(x: -44, y: -52)
                }
                .overlay(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, AppColors.brandPrimary.opacity(0.08)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 180, height: 100)
                        .blur(radius: 18)
                        .offset(x: 30, y: 22)
                }
        }
        .clipShape(shape)
    }
    
    // MARK: - Total Amount Section
    
    private var totalAmountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)

                        Button {
                            viewModel.handle(.showDisplayCurrencySheet)
                        } label: {
                            currencyPickerLabel(
                                symbol: MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency,
                                amountFontSize: 36,
                                color: AppColors.textSecondary.opacity(0.82)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let secondaryCurrency = viewModel.state.secondaryDisplayCurrency {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatBalance(viewModel.state.secondaryTotalAmount, isHidden: viewModel.state.isAmountHidden))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppColors.textTertiary)

                            Button {
                                viewModel.handle(.showSecondaryDisplayCurrencySheet)
                            } label: {
                                currencyPickerLabel(
                                    symbol: MonetaCurrency(rawValue: secondaryCurrency)?.symbol ?? secondaryCurrency,
                                    amountFontSize: 15,
                                    color: AppColors.textTertiary.opacity(0.82)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .offset(y: -2)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    headerActionButton(systemName: viewModel.state.isAmountHidden ? "eye.slash" : "eye") {
                        viewModel.handle(.toggleAmountVisibility)
                    }

                    headerActionButton(systemName: "gearshape") {
                        showFinanceSettingsSheet = true
                    }
                    .accessibilityLabel(financesLocalized("finances.common.settings"))
                }
            }

            if let warning = viewModel.state.currencyConversionWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.warning)

                    Text(financesLocalized("finances.main.warning.currency_api_partial"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppColors.warning.opacity(0.32), lineWidth: 1)
                        )
                )
                .accessibilityLabel(Text(warning))
            }
            
            // Полоса прогресса цели накопления
            if viewModel.state.isSavingsGoalEnabled && viewModel.state.savingsGoalAmount > 0 {
                VStack(spacing: 8) {
                    let progress: Double = {
                        let savingsGoal = viewModel.state.savingsGoalAmount
                        guard savingsGoal > 0 else { return 0.0 }
                        let calculated = viewModel.state.totalAmount / savingsGoal
                        guard calculated.isFinite else { return 0.0 }
                        return max(0.0, min(1.0, calculated))
                    }()
                    let displayCurrency = MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency
                    let totalText = formatBalance(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden)
                    let goalText = formatBalance(viewModel.state.savingsGoalAmount, isHidden: viewModel.state.isAmountHidden)
                    
                    goalProgressBar(progress: progress)
                    
                    HStack {
                        Text(FinancesL10n.format("finances.main.savings.progress", totalText, displayCurrency, goalText, displayCurrency))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.brandPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Spacer()
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.brandPrimary)
                    }
                }
                .padding(.top, 2)
            }
            
            if viewModel.state.isLoadingRates {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lastRefreshedLabel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func headerActionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(
                    width: FinanceScreenChrome.headerControlSide,
                    height: FinanceScreenChrome.headerControlSide
                )
                .background(
                    FinanceChromeCardBackground(
                        cornerRadius: FinanceScreenChrome.controlCornerRadius,
                        isElevated: false
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var heroModuleBackground: some View {
        FinanceChromeCardBackground(
            cornerRadius: FinancesMainLayoutPolicy.heroCornerRadius,
            isElevated: true
        )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill((AppColors.financesGradient.first ?? .cyan).opacity(0.12))
                    .blur(radius: 46)
                    .frame(width: 180, height: 180)
                    .offset(x: -44, y: -52)
            }
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppColors.brandPrimary.opacity(0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 180, height: 100)
                    .blur(radius: 18)
                    .offset(x: 30, y: 22)
            }
    }

    private var sectionModuleBackground: some View {
        FinanceChromeCardBackground(
            cornerRadius: FinancesMainLayoutPolicy.sectionCardCornerRadius
        )
    }
    
    // MARK: - Groups List Section
    
    private func groupsListSection(_ visibleGroups: [FinanceGroup]) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            if visibleGroups.isEmpty {
                emptyGroupsCallToAction
            } else {
                Text(financesLocalized("finances.main.accounts_section.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.84))
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)

                groupsListView(visibleGroups)
            }
        }
    }

    private func groupsListView(_ groups: [FinanceGroup]) -> some View {
        VStack(spacing: 10) {
            ForEach(groups) { group in
                FinanceGroupRow(
                    group: group,
                    viewModel: viewModel,
                    draggedGroupID: $draggedGroupID
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatBalance(_ balance: Double, isHidden: Bool = false) -> String {
        if isHidden {
            // Подсчитываем количество цифр в числе
            let digits = Int(balance.rounded())
            let digitCount = String(digits).count
            // Возвращаем точки вместо цифр
            return String(repeating: "•", count: max(3, digitCount))
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }

    private func currencyPickerLabel(
        symbol: String,
        amountFontSize: CGFloat,
        color: Color
    ) -> some View {
        let currencyFontSize = max(11, amountFontSize * 0.75)
        let chevronFontSize = max(7, amountFontSize * 0.28)

        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(symbol)
                .font(.system(size: currencyFontSize, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: chevronFontSize, weight: .bold))
                .foregroundStyle(color.opacity(0.9))
                .offset(y: -1)
        }
    }
    
    private func goalProgressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Capsule(style: .continuous)
                    .fill(AppColors.brandPrimary)
                    .frame(width: max(0, proxy.size.width * progress))
            }
        }
        .frame(height: 10)
    }

    private var emptyGroupsCallToAction: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()

                if !isEmptyIntroHidden {
                    Button {
                        isEmptyIntroHidden = true
                        FinancesEmptyStateIntroPrefs().setHidden(true)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(financesLocalized("finances.main.empty_intro.dismiss"))
                }
            }

            Image("finance")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .shadow(color: (AppColors.financesGradient.first ?? .cyan).opacity(0.18), radius: 16, y: 8)

            Text(financesLocalized("finances.main.empty_intro.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            if !isEmptyIntroHidden {
                Text(financesLocalized("finances.main.empty_intro.description"))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            Button {
                viewModel.handle(.showAddAccountSheet(nil))
            } label: {
                Text(financesLocalized("finances.main.empty_intro.add_product"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                (AppColors.financesGradient.first ?? .cyan).opacity(0.9),
                                                (AppColors.financesGradient.last ?? AppColors.brandPrimary).opacity(0.9)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)

        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background(
            FinanceChromeCardBackground(
                cornerRadius: FinancesMainLayoutPolicy.sectionCardCornerRadius,
                isElevated: true
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: FinancesMainLayoutPolicy.sectionCardCornerRadius,
                style: .continuous
            )
        )
        .padding(.top, 8)
    }

    private var addFloatingButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    viewModel.handle(.showAddAccountSheet(nil))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: FinancesMainLayoutPolicy.fabIconSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(
                            width: FinancesMainLayoutPolicy.fabDiameter,
                            height: FinancesMainLayoutPolicy.fabDiameter
                        )
                        .background(
                            FinanceChromeCardBackground(
                                cornerRadius: FinancesMainLayoutPolicy.fabDiameter / 2,
                                accentColor: AppColors.brandPrimary,
                                isElevated: true
                            )
                        )
                        .shadow(color: AppColors.brandPrimary.opacity(0.14), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.trailing, FinancesMainLayoutPolicy.fabTrailingPadding)
                .padding(.bottom, FinancesMainLayoutPolicy.fabBottomPadding)
            }
        }
    }
}

// MARK: - Finance Dynamics Tab View

struct FinanceDynamicsTabView: View {
    @ObservedObject var financeViewModel: FinanceViewModel
    
    var body: some View {
        FinanceDynamicsView(
            financeViewModel: financeViewModel,
            wrapInNavigationStack: false
        )
    }
}
