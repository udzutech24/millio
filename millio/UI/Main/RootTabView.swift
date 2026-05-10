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

    // Отдельные стеки для каждого таба
    @State private var dashboardPath = NavigationPath()
    @State private var financesPath = NavigationPath()
    @State private var dynamicsPath = NavigationPath()
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

    // Internal finances tab state (для обратной совместимости с FinancesContentViewInternal)
    @State private var financesInternalTab: FinancesInternalTab = .main

    private var isNavigatedDeep: Bool {
        switch router.selectedTab {
        case .dashboard: !dashboardPath.isEmpty
        case .finances:  !financesPath.isEmpty
        case .dynamics:  !dynamicsPath.isEmpty
        case .cashflow:  !cashflowPath.isEmpty
        }
    }

    var body: some View {
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
                RootTabBar(selectedTab: $router.selectedTab, showFABMenu: $showFABMenu) { fabAction in
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
        .onChange(of: router.pendingFABAction) { _, action in
            guard let action else { return }
            router.pendingFABAction = nil
            handleFABAction(action)
        }
        .sheet(isPresented: $showIncomeSheet) {
            if let vm = cashflowViewModel {
                CashflowIncomeTransactionSheet(viewModel: vm)
            }
        }
        .sheet(isPresented: $showExpenseSheet) {
            if let vm = cashflowViewModel {
                CashflowExpenseTransactionSheet(viewModel: vm)
            }
        }
        .sheet(isPresented: $showTransferSheet) {
            if let vm = cashflowViewModel {
                CashflowTransferTransactionSheet(viewModel: vm)
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
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        // Показываем только активный таб — ZStack с opacity для сохранения состояния
        ZStack {
            dashboardTab
                .opacity(router.selectedTab == .dashboard ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .dashboard)

            financesTab
                .opacity(router.selectedTab == .finances ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .finances)

            dynamicsTab
                .opacity(router.selectedTab == .dynamics ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .dynamics)

            cashflowTab
                .opacity(router.selectedTab == .cashflow ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .cashflow)
        }
    }

    // MARK: - Dashboard Tab

    private var dashboardTab: some View {
        NavigationStack(path: $dashboardPath) {
            DashboardView(
                onOpenConverter: { dashboardPath.append(FinancesStackRoute.courses) },
                onOpenCashback: { dashboardPath.append(FinancesStackRoute.cashback) },
                onAddIncome: {
                    ensureCashflowViewModel()
                    showIncomeSheet = true
                },
                onAddExpense: {
                    ensureCashflowViewModel()
                    showExpenseSheet = true
                },
                onAddTransfer: {
                    ensureCashflowViewModel()
                    showTransferSheet = true
                },
                onOpenFinances: { router.selectedTab = .finances },
                onOpenDynamics: { router.selectedTab = .dynamics },
                onOpenCashflow: { router.selectedTab = .cashflow },
                totalBalance: financeViewModel?.state.totalAmount ?? 0,
                displayCurrency: financeViewModel?.state.displayCurrency ?? appState.primaryCurrencyCode,
                sparklinePoints: financeViewModel?.state.dashboardSparkline ?? [],
                weekDelta: financeViewModel?.state.dashboardWeekDelta ?? (0.0, 0.0),
                sparklineDaysCount: financeViewModel?.state.dashboardSparklineDaysCount ?? 7,
                cashflowTotal: {
                    let s = cashflowViewModel?.state
                    return (s?.totalIncome ?? 0) + (s?.assetValueChange ?? 0) - (s?.contributedExpense ?? 0)
                }(),
                cashflowIncome: cashflowViewModel?.state.totalIncome ?? 0,
                cashflowExpense: cashflowViewModel?.state.contributedExpense ?? 0,
                cashflowAssetChange: cashflowViewModel?.state.assetValueChange ?? 0,
                cashflowCurrency: cashflowViewModel?.state.displayCurrency ?? appState.primaryCurrencyCode,
                cashflowPeriodLabel: cashflowViewModel?.state.chartPeriod.displayName ?? "Месяц"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        ensureCashflowViewModel()
                        appState.pendingOpenCashflowHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    profileButton
                }
            }
            .navigationDestination(for: FinancesStackRoute.self) { route in
                switch route {
                case .courses:
                    CoursesView()
                case .cashback:
                    CashbackView()
                }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    financeSettingsButton
                }
            }
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

    // MARK: - Profile Button

    private var profileButton: some View {
        let size: CGFloat = 34
        return Button {
            showProfileSheet = true
        } label: {
            Group {
                if let path = appState.profileAvatarPath,
                   FileManager.default.fileExists(atPath: path),
                   let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("profile")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Finance Settings Button

    @State private var showFinanceSettingsSheet = false

    private var financeSettingsButton: some View {
        Group {
            if financeViewModel != nil {
                Button {
                    showFinanceSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showFinanceSettingsSheet) {
                    if let vm = financeViewModel {
                        FinancesSettingsSheetWrapper(viewModel: vm, modelContext: modelContext)
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Dynamics Tab

    private var dynamicsTab: some View {
        NavigationStack(path: $dynamicsPath) {
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
            let vm = CashflowViewModel(modelContext: modelContext)
            vm.handle(.syncDisplayCurrencyWithPrimary(appState.primaryCurrencyCode))
            vm.handle(.loadCards)
            vm.handle(.loadTransactions)
            cashflowViewModel = vm
        }
    }
}

// MARK: - Finance Settings Sheet Wrapper

/// Обёртка для FinancesSettingsSheet с поддержкой sheet-модальных экранов
struct FinancesSettingsSheetWrapper: View {
    @ObservedObject var viewModel: FinanceViewModel
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showBalanceAudit = false
    @State private var showMassTickerImport = false

    private var isDailyAuditAvailable: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    var body: some View {
        FinancesSettingsSheet(
            isDailyAuditAvailable: isDailyAuditAvailable,
            onOpenSavingsGoal: {
                dismiss()
                viewModel.handle(.showSavingsGoalSheet)
            },
            onOpenDailyAudit: {
                guard isDailyAuditAvailable else { return }
                dismiss()
                showBalanceAudit = true
            },
            onOpenMassTickerImport: {
                dismiss()
                showMassTickerImport = true
            }
        )
        .sheet(isPresented: $showBalanceAudit) {
            if isDailyAuditAvailable {
                FinanceBalanceAuditSheet(
                    financeViewModel: viewModel,
                    modelContext: modelContext
                )
            }
        }
        .sheet(isPresented: $showMassTickerImport) {
            StockBulkImportSheet(
                financeViewModel: viewModel,
                modelContext: modelContext,
                marketDataClient: viewModel.marketDataClient
            )
        }
    }
}
