//
//  RootTabView.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Финансы: маршруты внутреннего стека

enum FinancesStackRoute: Hashable {
    case courses
    case cashback
}

// MARK: - Root Tab View

struct RootTabView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.diContainer) private var diContainer

    // Отдельные стеки для каждого таба
    @State private var dashboardPath = NavigationPath()
    @State private var financesPath = NavigationPath()
    @State private var cashflowPath = NavigationPath()

    // ViewModels (ленивая инициализация)
    @State private var financeViewModel: FinanceViewModel?
    @State private var cashflowViewModel: CashflowViewModel?

    // FAB menu
    @State private var showFABMenu = false

    // FAB / quick-action sheets
    @State private var showIncomeSheet = false
    @State private var showExpenseSheet = false
    @State private var showTransferSheet = false

    // Profile
    @State private var showProfileSheet = false
    @State private var showDeltaPeriodPicker = false
    @State private var dashboardPeriodDays: Int = SettingsManager.shared.dashboardDeltaPeriodDays

    // Internal finances tab state (для обратной совместимости с FinancesContentViewInternal)
    @State private var financesInternalTab: FinancesInternalTab = .main

    /// Счётчик сбросов на вкладку. Инкремент меняет `.id` контента вкладки → SwiftUI
    /// пересоздаёт её `NavigationStack` и раздел открывается на корневом экране.
    /// Почему не только очистка path: вглубь (счёт → позиция) экраны уходят через
    /// view-based `NavigationLink { … }`, а такие переходы в `NavigationPath` не попадают,
    /// поэтому обнуления пути недостаточно.
    @State private var tabResetTokens: [RootTab: Int] = [:]

    private var isNavigatedDeep: Bool {
        switch router.selectedTab {
        case .dashboard: !dashboardPath.isEmpty
        case .finances:  !financesPath.isEmpty
        case .dynamics:  false
        case .cashflow:  !cashflowPath.isEmpty
        }
    }

    @ViewBuilder var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MILLIO_DEBIT_CARD_QA"] == "1" {
            DebitCardQAHarness(modelContext: modelContext)
        } else if ProcessInfo.processInfo.environment["MILLIO_REAL_ESTATE_HOTFIX_QA"] == "1" {
            RealEstateEditQAHarness(modelContext: modelContext)
        } else {
            productionBody
        }
        #else
        productionBody
        #endif
    }

    private var productionBody: some View {
        ZStack(alignment: .bottom) {
            // Контент таба
            tabContent

            // Tap-to-dismiss FAB menu при нажатии вне
            if showFABMenu {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                            showFABMenu = false
                        }
                    }
            }

            // Кастомный таб бар — скрываем при push-навигации вглубь
            if !isNavigatedDeep {
                RootTabBar(
                    selectedTab: $router.selectedTab,
                    showFABMenu: $showFABMenu,
                    onReselectTab: { tab in resetTabToRoot(tab) }
                ) { fabAction in
                    handleFABAction(fabAction)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isNavigatedDeep)
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            ensureViewModels()
            consumePendingDeepLinks()
        }
        .onChange(of: appState.pendingOpenConverterService) { _, _ in consumePendingDeepLinks() }
        .onChange(of: appState.pendingOpenMainExpenseSheet) { _, _ in consumePendingDeepLinks() }
        .onChange(of: appState.pendingOpenMainIncomeSheet) { _, _ in consumePendingDeepLinks() }
        .onChange(of: appState.pendingOpenCashflowExpense) { _, _ in consumePendingDeepLinks() }
        .onChange(of: appState.pendingOpenCashflowIncome) { _, _ in consumePendingDeepLinks() }
        .onChange(of: appState.pendingOpenCashflowHistory) { _, _ in consumePendingDeepLinks() }
        .onChange(of: appState.primaryCurrencyCode) { _, _ in ensureViewModels() }
        .onChange(of: router.selectedTab) { _, _ in
            guard showFABMenu else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                showFABMenu = false
            }
        }
        .onChange(of: router.pendingFABAction) { _, action in
            guard let action else { return }
            router.pendingFABAction = nil
            handleFABAction(action)
        }
        .sheet(isPresented: $showIncomeSheet) {
            if let vm = cashflowViewModel {
                CashflowUnifiedEntryContainer(viewModel: vm, initialTab: .incomes)
            }
        }
        .sheet(isPresented: $showExpenseSheet) {
            if let vm = cashflowViewModel {
                CashflowUnifiedEntryContainer(viewModel: vm, initialTab: .expenses)
            }
        }
        .sheet(isPresented: $showTransferSheet) {
            if let vm = cashflowViewModel {
                // Ф3: раньше здесь открывался старый двухшаговый CashflowTransferTransactionSheet
                // в обход единого экрана (в отличие от FAB внутри самого таба Cashflow, который уже
                // шёл через CashflowUnifiedEntryContainer, см. CashflowView.swift). Приводим к единому
                // поведению — Перевод из глобального FAB/Dashboard тоже открывает unified-контейнер
                // с сегмент-пикером Расход|Доход|Перевод.
                CashflowUnifiedEntryContainer(viewModel: vm, initialTab: .transfer)
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            NavigationStack {
                ProfileView(router: router)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $router.showingSubscription) {
            NavigationStack {
                SubscriptionView()
            }
            .environment(appState)
        }
        .sheet(isPresented: $showDeltaPeriodPicker) {
            DashboardDeltaPeriodPickerSheet(selectedPeriod: $dashboardPeriodDays)
                .presentationDetents([.fraction(0.32)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: incomingStatementBinding) { item in
            if let financeViewModel, let cashflowViewModel {
                IncomingStatementDestinationView(
                    item: item,
                    financeViewModel: financeViewModel,
                    cashflowViewModel: cashflowViewModel,
                    statementClient: statementImportClient,
                    complete: { finishIncomingStatement(item) },
                    discard: { finishIncomingStatement(item) }
                )
            }
        }
        .sheet(item: appliedPlannedNoticeBinding) { item in
            // Ф2: заглушка — только число применённых операций. Настоящий лист (суммы по валютам,
            // раскрытие в список, «и ещё N») — Ф3 плана, локализация — Ф5.
            AppliedPlannedNoticeStubSheet(digest: item.digest)
        }
        .onChange(of: dashboardPeriodDays) { _, newValue in
            SettingsManager.shared.dashboardDeltaPeriodDays = newValue
            showDeltaPeriodPicker = false
            Task { await financeViewModel?.computeDashboardSparkline() }
        }
    }

    private var incomingStatementBinding: Binding<IncomingStatementInboxItem?> {
        Binding(
            get: {
                guard !showIncomeSheet,
                      !showExpenseSheet,
                      !showTransferSheet,
                      !showProfileSheet,
                      !router.showingSubscription,
                      !showDeltaPeriodPicker,
                      !appState.isStatementOnboardingActive,
                      appState.pendingIncomingBackupURL == nil else { return nil }
                return appState.pendingIncomingStatementItem
            },
            set: { value in appState.pendingIncomingStatementItem = value }
        )
    }

    /// Взаимоисключение листов здесь ручное (очереди в проекте нет) — сводка ждёт, пока экран
    /// свободен. Лист выписки в этом списке тоже: он приоритетнее сводки.
    private var appliedPlannedNoticeBinding: Binding<AppliedPlannedNoticeItem?> {
        Binding(
            get: {
                guard !showIncomeSheet,
                      !showExpenseSheet,
                      !showTransferSheet,
                      !showProfileSheet,
                      !router.showingSubscription,
                      !showDeltaPeriodPicker,
                      !appState.isStatementOnboardingActive,
                      appState.pendingIncomingStatementItem == nil,
                      appState.pendingIncomingBackupURL == nil else { return nil }
                return appState.pendingAppliedPlannedNotice
            },
            set: { value in appState.pendingAppliedPlannedNotice = value }
        )
    }

    private var statementImportClient: any CashflowStatementImportClient {
        guard let diContainer else { return UnavailableCashflowStatementImportClient() }
        return diContainer.apiClientFactory.makeCashflowStatementImportClient(authService: diContainer.authService)
    }

    private func finishIncomingStatement(_ item: IncomingStatementInboxItem) {
        do {
            try IncomingStatementCoordinator.appGroup().complete(item)
        } catch {
            AppLogger.log(.error, category: "StatementIngress", "Statement cleanup failed code=cleanup_failed")
        }
        appState.pendingIncomingStatementItem = nil
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        // Показываем только активный таб — ZStack с opacity для сохранения состояния
        ZStack {
            dashboardTab
                .id(resetToken(for: .dashboard))
                .opacity(router.selectedTab == .dashboard ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .dashboard)

            financesTab
                .id(resetToken(for: .finances))
                .opacity(router.selectedTab == .finances ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .finances)

            dynamicsTab
                .id(resetToken(for: .dynamics))
                .opacity(router.selectedTab == .dynamics ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .dynamics)

            cashflowTab
                .id(resetToken(for: .cashflow))
                .opacity(router.selectedTab == .cashflow ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .cashflow)
        }
    }

    // MARK: - Reselect → Root

    private func resetToken(for tab: RootTab) -> Int {
        tabResetTokens[tab] ?? 0
    }

    /// Тап по уже активной вкладке возвращает раздел на корневой экран.
    /// Модальные листы закрываем вместе со сбросом, чтобы лист не завис поверх нового корня.
    private func resetTabToRoot(_ tab: RootTab) {
        dismissPresentedSheets()

        switch tab {
        case .dashboard: dashboardPath = NavigationPath()
        case .finances:  financesPath = NavigationPath()
        case .dynamics:  break
        case .cashflow:  cashflowPath = NavigationPath()
        }

        tabResetTokens[tab] = resetToken(for: tab) + 1
    }

    private func dismissPresentedSheets() {
        showIncomeSheet = false
        showExpenseSheet = false
        showTransferSheet = false
        showProfileSheet = false
        showDeltaPeriodPicker = false
        router.showingSubscription = false
    }

    // MARK: - Dashboard Tab

    @ViewBuilder
    private var dashboardTab: some View {
        if let fvm = financeViewModel, let cvm = cashflowViewModel {
            DashboardTabHostView(
                financeViewModel: fvm,
                cashflowViewModel: cvm,
                path: $dashboardPath,
                onAddIncome: { ensureCashflowViewModel(); showIncomeSheet = true },
                onAddExpense: { ensureCashflowViewModel(); showExpenseSheet = true },
                onAddTransfer: { ensureCashflowViewModel(); showTransferSheet = true },
                onOpenFinances: { router.selectedTab = .finances },
                onOpenDynamics: { router.selectedTab = .dynamics },
                onOpenCashflow: { router.selectedTab = .cashflow },
                onOpenHistory: { ensureCashflowViewModel(); appState.pendingOpenCashflowHistory = true },
                onShowProfile: { showProfileSheet = true },
                onDaysChipTap: { showDeltaPeriodPicker = true }
            )
        } else {
            NavigationStack(path: $dashboardPath) {
                Color.clear.navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Finances Tab

    private var financesTab: some View {
        NavigationStack(path: $financesPath) {
            ZStack {
                GradientBackground()

                VStack(spacing: 0) {
                    // Основной контент
                    if let vm = financeViewModel {
                        FinancesMainTabView(
                            viewModel: vm,
                            selectedTab: $financesInternalTab,
                            onNavigateToDynamics: {
                                router.selectedTab = .dynamics
                            }
                        )
                    } else {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.bottom, 72) // отступ под таб бар
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FinancesStackRoute.self) { route in
                switch route {
                case .courses:
                    CoursesView()
                case .cashback:
                    CashbackView()
                }
            }
        }
        .onAppear {
            FinancesDeepLinkHandler.openAddCardIfRequested(
                appState: appState,
                viewModel: financeViewModel
            )
        }
        .onChange(of: appState.pendingOpenFinanceAddCard) { _, _ in
            FinancesDeepLinkHandler.openAddCardIfRequested(appState: appState, viewModel: financeViewModel)
        }
        .onChange(of: appState.primaryCurrencyCode) { oldValue, newValue in
            financeViewModel?.handle(.syncPrimaryCurrencyChange(old: oldValue, new: newValue))
        }
    }

    // MARK: - Dynamics Tab

    private var dynamicsTab: some View {
        ZStack {
            GradientBackground()

            if let vm = financeViewModel {
                FinanceDynamicsTabView(financeViewModel: vm)
                    .padding(.bottom, 72)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
    }

    // MARK: - Cashflow Tab

    private var cashflowTab: some View {
        NavigationStack(path: $cashflowPath) {
            ZStack {
                GradientBackground()
                CashflowView(isTabMode: true, sharedViewModel: cashflowViewModel)
                    .padding(.bottom, 72)
            }
        }
    }

    // MARK: - Deep Link Handler

    private func consumePendingDeepLinks() {
        // Конвертер → Финансы → push Courses
        if appState.pendingOpenConverterService {
            appState.pendingOpenConverterService = false
            router.selectedTab = .finances
            financesPath = NavigationPath()
            financesPath.append(FinancesStackRoute.courses)
        }

        // Основной расход → FAB expense
        if appState.pendingOpenMainExpenseSheet {
            appState.pendingOpenMainExpenseSheet = false
            ensureCashflowViewModel()
            showExpenseSheet = true
        }

        // Основной доход → FAB income
        if appState.pendingOpenMainIncomeSheet {
            appState.pendingOpenMainIncomeSheet = false
            ensureCashflowViewModel()
            showIncomeSheet = true
        }

        // Кэшфлоу deep links → переключаем таб, CashflowView сам обработает флаги
        if appState.pendingOpenCashflowExpense
            || appState.pendingOpenCashflowIncome
            || appState.pendingOpenCashflowHistory {
            router.selectedTab = .cashflow
        }
    }

    // MARK: - FAB Handler

    private func handleFABAction(_ action: FABAction) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
            showFABMenu = false
        }
        ensureCashflowViewModel()
        switch action {
        case .income:
            showIncomeSheet = true
        case .expense:
            showExpenseSheet = true
        case .transfer:
            showTransferSheet = true
        }
    }

    // MARK: - ViewModel Setup

    private func ensureViewModels() {
        ensureFinanceViewModel()
        ensureCashflowViewModel()
    }

    private func ensureFinanceViewModel() {
        guard financeViewModel == nil else { return }
        financeViewModel = FinanceViewModel(modelContext: modelContext)
    }

    private func ensureCashflowViewModel() {
        if cashflowViewModel == nil {
            let vm = CashflowViewModel(
                modelContext: modelContext,
                sheetsExportTrigger: SheetsExportAvailability.isEnabled
                    ? diContainer?.sheetsExportTrigger
                    : nil
            )
            // Сводку показывает гейт готовности в millioApp — VM только сообщает, что журнал
            // пополнился. Прямой показ отсюда обошёл бы блокировку и очередь листов.
            vm.onPlannedOperationsApplied = { [appState] in
                appState.appliedPlannedNoticeRequestToken &+= 1
            }
            vm.handle(.syncDisplayCurrencyWithPrimary(appState.primaryCurrencyCode))
            vm.handle(.loadCards)
            vm.handle(.loadTransactions)
            cashflowViewModel = vm
        }
    }
}

// MARK: - Dashboard Tab Host

/// Отдельная view для таба Dashboard, чтобы @ObservedObject корректно
/// подписывался на изменения FinanceViewModel/@CashflowViewModel.
/// Без этого @State в RootTabView не реагирует на @Published-изменения внутри VM
/// и дашборд остаётся с нулями до следующего ре-рендера родителя.
private struct DashboardTabHostView: View {
    @ObservedObject var financeViewModel: FinanceViewModel
    @ObservedObject var cashflowViewModel: CashflowViewModel
    @Binding var path: NavigationPath
    @Environment(AppState.self) private var appState

    var onAddIncome: () -> Void
    var onAddExpense: () -> Void
    var onAddTransfer: () -> Void
    var onOpenFinances: () -> Void
    var onOpenDynamics: () -> Void
    var onOpenCashflow: () -> Void
    var onOpenHistory: () -> Void
    var onShowProfile: () -> Void
    var onDaysChipTap: () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            DashboardView(
                onOpenConverter: { path.append(FinancesStackRoute.courses) },
                onOpenCashback: { path.append(FinancesStackRoute.cashback) },
                onAddIncome: onAddIncome,
                onAddExpense: onAddExpense,
                onAddTransfer: onAddTransfer,
                onOpenFinances: onOpenFinances,
                onOpenDynamics: onOpenDynamics,
                onOpenCashflow: onOpenCashflow,
                totalBalance: financeViewModel.state.totalAmount,
                displayCurrency: financeViewModel.state.displayCurrency,
                sparklinePoints: financeViewModel.state.dashboardSparkline,
                weekDelta: financeViewModel.state.dashboardWeekDelta,
                sparklineDaysCount: financeViewModel.state.dashboardSparklineDaysCount,
                cashflowTotal: {
                    let s = cashflowViewModel.state
                    return s.totalIncome + s.assetValueChange - s.contributedExpense
                }(),
                cashflowIncome: cashflowViewModel.state.totalIncome,
                cashflowExpense: cashflowViewModel.state.contributedExpense,
                cashflowAssetChange: cashflowViewModel.state.assetValueChange,
                cashflowCurrency: cashflowViewModel.state.displayCurrency,
                cashflowPeriodLabel: cashflowViewModel.state.chartPeriod.displayName,
                onOpenHistory: onOpenHistory,
                onShowProfile: onShowProfile,
                onDaysChipTap: onDaysChipTap
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FinancesStackRoute.self) { route in
                switch route {
                case .courses: CoursesView()
                case .cashback: CashbackView()
                }
            }
        }
    }
}

// MARK: - Finance Settings Sheet Wrapper

/// Обёртка для FinancesSettingsSheet с поддержкой sheet-модальных экранов
struct FinancesSettingsSheetWrapper: View {
    @ObservedObject var viewModel: FinanceViewModel
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showMassTickerImport = false

    var body: some View {
        FinancesSettingsSheet(
            viewModel: viewModel,
            accountSortMode: Binding(
                get: { viewModel.state.accountSortMode },
                set: { viewModel.handle(.setAccountSortMode($0)) }
            ),
            onOpenSavingsGoal: {
                dismiss()
                viewModel.handle(.showSavingsGoalSheet)
            },
            onOpenMassTickerImport: {
                dismiss()
                showMassTickerImport = true
            }
        )
        .sheet(isPresented: $showMassTickerImport) {
            StockBulkImportSheet(
                financeViewModel: viewModel,
                modelContext: modelContext,
                marketDataClient: viewModel.marketDataClient
            )
        }
    }
}
