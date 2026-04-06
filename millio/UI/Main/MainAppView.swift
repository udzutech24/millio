//
//  MainAppView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SwiftData

@MainActor
enum MainWidgetDeepLinkHandler {
    static func consumePendingActions(
        appState: AppState,
        router: AppRouter
    ) {
        if appState.pendingOpenConverterService {
            appState.pendingOpenConverterService = false
            router.navigationPath = NavigationPath()
            router.push(.courses)
        }

        if appState.pendingOpenMainExpenseSheet {
            appState.pendingOpenMainExpenseSheet = false
            appState.pendingOpenCashflowExpense = true
            router.navigationPath = NavigationPath()
            router.push(.cashflow)
        }

        if appState.pendingOpenMainIncomeSheet {
            appState.pendingOpenMainIncomeSheet = false
            appState.pendingOpenCashflowIncome = true
            router.navigationPath = NavigationPath()
            router.push(.cashflow)
        }
    }
}

struct MainAppView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: MainAppViewModel
    @State private var services: [ServiceItem] = []
    @State private var draggedService: ServiceItem?
    @State private var cashflowViewModel: CashflowViewModel?
    @State private var financeDashboardViewModel: FinanceViewModel?
    @State private var financeDashboardDynamicsViewModel: FinanceDynamicsViewModel?
    @State private var showExpenseSheet = false
    @State private var showIncomeSheet = false
    @State private var showCashflowHistory = false
    @State private var showQuickSetupSheet = false
    @State private var showQuickSetupBanner = false
    @State private var showDashboardEditSheet = false
    @State private var dashboardWidgetConfigs = DashboardLayoutStore.defaultConfigurations
    @State private var converterDashboardRates: [String: Double] = ["USD": 1.0]
    private let serviceOrderManager = ServiceOrderManager()
    private let dashboardLayoutStore = DashboardLayoutStore()
    
    init(router: AppRouter) {
        self.router = router
        _viewModel = StateObject(wrappedValue: MainAppViewModel(router: router))
    }
    
    var body: some View {
        NavigationStack(path: $router.navigationPath) {
            ZStack {
                mainScreenBackground
                mainContent
            }
            .navigationDestination(for: AppRoute.self) { route in
                routeView(for: route)
            }
            .sheet(isPresented: $showExpenseSheet) {
                if let cashflowViewModel = cashflowViewModel {
                    CashflowExpenseTransactionSheet(viewModel: cashflowViewModel)
                }
            }
            .sheet(isPresented: $showIncomeSheet) {
                if let cashflowViewModel = cashflowViewModel {
                    CashflowIncomeTransactionSheet(viewModel: cashflowViewModel)
                }
            }
            .sheet(isPresented: $showCashflowHistory) {
                if let cashflowViewModel = cashflowViewModel {
                    CashflowTransactionsHistoryView(viewModel: cashflowViewModel)
                }
            }
            .sheet(isPresented: $showQuickSetupSheet) {
                QuickSetupView(
                    appState: appState,
                    mode: .settings,
                    onCompleted: {
                        showQuickSetupBanner = false
                    }
                )
            }
            .sheet(isPresented: $showDashboardEditSheet) {
                DashboardEditView(configs: dashboardWidgetConfigs) { configs in
                    dashboardWidgetConfigs = configs
                    dashboardLayoutStore.save(configs)
                }
            }
            .onAppear {
                loadServices()
                dashboardWidgetConfigs = dashboardLayoutStore.load()
                refreshConverterDashboardRates()
                prepareFinanceDashboardAccess()
                showQuickSetupBanner = !SettingsManager.shared.isQuickSetupCompleted
                    && !SettingsManager.shared.isQuickSetupBannerHidden
                prepareCashflowQuickAccess()
                MainWidgetDeepLinkHandler.consumePendingActions(
                    appState: appState,
                    router: router
                )
            }
            .onChange(of: appState.primaryCurrencyCode) { _, _ in
                refreshConverterDashboardRates()
                prepareCashflowQuickAccess()
                prepareFinanceDashboardAccess()
            }
            .onChange(of: showExpenseSheet) { _, isPresented in
                if isPresented {
                    prepareCashflowQuickAccess()
                }
            }
            .onChange(of: showIncomeSheet) { _, isPresented in
                if isPresented {
                    prepareCashflowQuickAccess()
                }
            }
            .onChange(of: showCashflowHistory) { _, isPresented in
                if isPresented {
                    prepareCashflowQuickAccess()
                }
            }
            .onChange(of: appState.pendingOpenConverterService) { _, _ in
                MainWidgetDeepLinkHandler.consumePendingActions(
                    appState: appState,
                    router: router
                )
            }
            .onChange(of: appState.pendingOpenMainExpenseSheet) { _, _ in
                MainWidgetDeepLinkHandler.consumePendingActions(
                    appState: appState,
                    router: router
                )
            }
            .onChange(of: appState.pendingOpenMainIncomeSheet) { _, _ in
                MainWidgetDeepLinkHandler.consumePendingActions(
                    appState: appState,
                    router: router
                )
            }
        }
    }

    private var mainScreenBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [
                    AppColors.brandPrimary.opacity(0.26),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 380
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(hex: "0A111C").opacity(0.8),
                    Color.black,
                    Color(hex: "05070B")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppColors.quickSetupAccentMint.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 130, y: 180)
        }
    }

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                heroSection

                if showQuickSetupBanner {
                    quickSetupBanner
                }

                dashboardWidgetStack

                dashboardEditFooterButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                viewModel.handle(.navigateToProfile)
            } label: {
                headerProfileImage
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text("Главная")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(heroSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                openCashflowHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MainLocalization.text(MainLocalization.historyAccessibility))
        }
        .padding(.top, 8)
    }

    private var heroSubtitle: String {
        let dateText = Date().formatted(
            Date.FormatStyle(date: .complete, time: .omitted)
                .locale(AppLocalization.currentAppLocale)
        )
        return "\(dateText). Быстрый доступ к сервисам, операциям и обзору денег."
    }

    private func header(showsHistoryButton: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.handle(.navigateToProfile)
            } label: {
                headerProfileImage
            }

            Spacer(minLength: 12)

            if showsHistoryButton {
                Button {
                    openCashflowHistory()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.95), lineWidth: 1.3)
                        )
                }
                .accessibilityLabel(MainLocalization.text(MainLocalization.historyAccessibility))
            }
        }
    }
    
    private var headerProfileImage: some View {
        let size: CGFloat = 40
        return Group {
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

    private var quickSetupBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(MainLocalization.text(MainLocalization.quickSetupBannerTitle))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(MainLocalization.text(MainLocalization.quickSetupBannerSubtitle))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)

                Button {
                    showQuickSetupSheet = true
                } label: {
                    Text(MainLocalization.text(MainLocalization.quickSetupBannerOpen))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppColors.quickSetupAccent.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            Spacer()

            Button {
                showQuickSetupBanner = false
                SettingsManager.shared.isQuickSetupBannerHidden = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .mainSectionSurface(tint: AppColors.quickSetupAccentMint, cornerRadius: 28)
    }
    
    // MARK: - Services Grid
    
    private var servicesGrid: some View {
        VStack(spacing: 12) {
            ForEach(services) { service in
                ServiceButton(
                    title: MainLocalization.text(service.titleKey),
                    icon: service.icon,
                    gradientColors: service.gradientColors
                ) {
                    viewModel.handle(.navigateToService(service.route))
                }
                .frame(maxWidth: .infinity)
                .opacity(draggedService?.id == service.id ? 0.75 : 1.0)
                .onDrag {
                    draggedService = service
                    return NSItemProvider(object: NSString(string: service.id))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ServiceReorderDropDelegate(
                        targetService: service,
                        services: $services,
                        draggedService: $draggedService,
                        onReorderFinished: persistServiceOrder
                    )
                )
            }
        }
    }

    private var focusServicesGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ],
            spacing: 14
        ) {
            ForEach(services) { service in
                MainServiceCard(
                    title: MainLocalization.text(service.titleKey),
                    icon: service.icon,
                    gradientColors: service.gradientColors
                ) {
                    viewModel.handle(.navigateToService(service.route))
                }
                .opacity(draggedService?.id == service.id ? 0.72 : 1.0)
                .onDrag {
                    draggedService = service
                    return NSItemProvider(object: NSString(string: service.id))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ServiceReorderDropDelegate(
                        targetService: service,
                        services: $services,
                        draggedService: $draggedService,
                        onReorderFinished: persistServiceOrder
                    )
                )
            }
        }
    }

    private var quickActionsRow: some View {
        HStack(spacing: 16) {
            ForEach(MainQuickActionsLayout.buttonOrder, id: \.self) { action in
                switch action {
                case .expense:
                    ActionButton(
                        title: MainLocalization.text(MainLocalization.quickActionExpense),
                        icon: .system(QuickActionIcons.expense),
                        gradientColors: AppColors.expenseGradient
                    ) {
                        openExpenseSheet()
                    }
                case .income:
                    ActionButton(
                        title: MainLocalization.text(MainLocalization.quickActionIncome),
                        icon: .system(QuickActionIcons.income),
                        gradientColors: AppColors.incomeGradient
                    ) {
                        openIncomeSheet()
                    }
                }
            }
        }
    }

    private var dashboardEditBar: some View {
        EmptyView()
    }

    private var dashboardEditFooterButton: some View {
        Button {
            showDashboardEditSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text("Настроить экран")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .mainInnerSurface(tint: AppColors.brandPrimary, cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }

    private var dashboardWidgetStack: some View {
        let rows = dashboardWidgetRows(availableWidth: mainContentWidth)

        return VStack(spacing: 16) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row.count == 2 {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(row, id: \.self) { kind in
                            dashboardWidget(for: kind, compactMode: true)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .frame(height: 250, alignment: .top)
                        }
                    }
                } else if let kind = row.first {
                    dashboardWidget(for: kind)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var mainContentWidth: CGFloat {
        max(UIScreen.main.bounds.width - 40, 320)
    }

    private var visibleDashboardWidgetConfigs: [DashboardWidgetConfig] {
        dashboardWidgetConfigs
            .filter(\.isVisible)
            .sorted { $0.order < $1.order }
    }

    private var visibleDashboardWidgetKinds: [DashboardWidgetKind] {
        visibleDashboardWidgetConfigs.map(\.kind)
    }

    private func dashboardWidgetRows(availableWidth: CGFloat) -> [[DashboardWidgetKind]] {
        DashboardWidgetLayoutPlanner.rows(
            for: visibleDashboardWidgetKinds,
            availableWidth: availableWidth
        )
    }

    @ViewBuilder
    private func dashboardWidget(
        for kind: DashboardWidgetKind,
        compactMode: Bool = false
    ) -> some View {
        switch kind {
        case .converter:
            converterDashboardWidget(compactMode: compactMode)
        case .quickActions:
            quickActionsDashboardWidget(compactMode: compactMode)
        case .finances:
            if let financeDashboardViewModel, let financeDashboardDynamicsViewModel {
                FinanceDashboardWidget(
                    financeViewModel: financeDashboardViewModel,
                    dynamicsViewModel: financeDashboardDynamicsViewModel,
                    onOpenFinances: {
                        viewModel.handle(.navigateToService(.finances))
                    },
                        onAddProduct: openFinanceAddProduct
                )
            }
        case .services:
            servicesDashboardWidget
        case .cashflow:
            if let cashflowViewModel {
                CashflowDashboardWidget(
                    viewModel: cashflowViewModel,
                    onOpenCashflow: {
                        viewModel.handle(.navigateToService(.cashflow))
                    }
                )
            }
        }
    }

    private func quickActionsDashboardWidget(compactMode: Bool) -> some View {
        MainQuickActionsDashboardWidget(
            compactMode: compactMode,
            incomeTitle: MainLocalization.text(MainLocalization.quickActionIncome),
            expenseTitle: MainLocalization.text(MainLocalization.quickActionExpense),
            historyTitle: MainLocalization.text(MainLocalization.quickActionHistory),
            historySubtitle: MainLocalization.text(MainLocalization.historyAccessibility),
            onIncomeTap: openIncomeSheet,
            onExpenseTap: openExpenseSheet,
            onHistoryTap: openCashflowHistory
        )
    }

    private func converterDashboardWidget(compactMode: Bool) -> some View {
        VStack(alignment: .leading, spacing: compactMode ? 10 : 12) {
            Text(MainLocalization.dashboardWidgetTitle(for: .converter))
                .font(.system(size: compactMode ? 17 : 21, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            if !compactMode {
                Text(MainLocalization.dashboardWidgetSubtitle(for: .converter))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Button {
                viewModel.handle(.navigateToService(.courses))
            } label: {
                VStack(spacing: 0) {
                    ForEach(Array(converterDashboardQuotes.enumerated()), id: \.element.targetCode) { index, quote in
                        converterDashboardRow(quote: quote, compactMode: compactMode)

                        if index < converterDashboardQuotes.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                                .padding(.leading, compactMode ? 0 : 54)
                        }
                    }
                }
                .padding(.horizontal, compactMode ? 12 : 14)
                .padding(.vertical, 6)
                .mainInnerSurface(
                    tint: AppColors.coursesGradient.first ?? AppColors.brandPrimary,
                    cornerRadius: 24
                )
            }
            .buttonStyle(.plain)
        }
        .padding(compactMode ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mainSectionSurface(
            tint: AppColors.coursesGradient.first ?? AppColors.brandPrimary,
            cornerRadius: 30
        )
    }

    private var servicesDashboardWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MainLocalization.dashboardWidgetTitle(for: .services))
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(MainLocalization.dashboardWidgetSubtitle(for: .services))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)

            focusServicesGrid
        }
        .padding(20)
        .mainSectionSurface(tint: AppColors.brandPrimary, cornerRadius: 30)
    }

    private var converterDashboardQuotes: [MainConverterDashboardQuote] {
        MainConverterDashboardSupport.quotes(
            primaryCode: appState.primaryCurrencyCode,
            favoriteCodes: SettingsManager.shared.favoriteCurrencyCodes,
            rates: converterDashboardRates,
            locale: AppLocalization.currentAppLocale
        )
    }

    private func converterDashboardRow(
        quote: MainConverterDashboardQuote,
        compactMode: Bool
    ) -> some View {
        Group {
            if compactMode {
                HStack(spacing: 8) {
                    Text(CurrencyFlags.flag(for: quote.targetCode))
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )

                    Text(quote.targetCode)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer(minLength: 8)

                    Text(compactRateValue(from: quote.rateSummary))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            } else {
                HStack(spacing: 12) {
                    Text(CurrencyFlags.flag(for: quote.targetCode))
                        .font(.system(size: 18))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(quote.targetCode)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(quote.baseSummary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: 8)

                    Text(quote.rateSummary)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }
            }
        }
        .padding(.vertical, compactMode ? 10 : 11)
        .contentShape(Rectangle())
    }

    private func compactRateValue(from summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastSpaceIndex = trimmed.lastIndex(of: " ") else { return trimmed }
        return String(trimmed[..<lastSpaceIndex])
    }
    
    // MARK: - Helpers
    
    private func loadServices() {
        services = serviceOrderManager.getOrderedServices()
    }

    private func persistServiceOrder() {
        serviceOrderManager.saveOrder(services.map(\.id))
    }

    private func refreshConverterDashboardRates() {
        let snapshot = CurrencyWidgetShared.ConverterSnapshot.load(from: UserDefaults.standard)
        converterDashboardRates = snapshot.rates
    }

    private func prepareCashflowQuickAccess() {
        let viewModel = CashflowViewModel(modelContext: modelContext)
        viewModel.handle(.syncDisplayCurrencyWithPrimary(appState.primaryCurrencyCode))
        viewModel.handle(.loadCards)
        viewModel.handle(.loadTransactions)
        cashflowViewModel = viewModel
    }

    private func prepareFinanceDashboardAccess() {
        if financeDashboardViewModel == nil {
            financeDashboardViewModel = FinanceViewModel(modelContext: modelContext)
        }
        if financeDashboardDynamicsViewModel == nil, let financeDashboardViewModel {
            let dynamicsViewModel = FinanceDynamicsViewModel(
                modelContext: modelContext,
                financeViewModel: financeDashboardViewModel
            )
            dynamicsViewModel.handle(.setPeriod(.week))
            financeDashboardDynamicsViewModel = dynamicsViewModel
        }
        financeDashboardViewModel?.handle(
            .setDisplayCurrency(appState.primaryCurrencyCode)
        )
        financeDashboardViewModel?.handle(.loadGroups)
        financeDashboardViewModel?.handle(.loadAccounts)
        financeDashboardDynamicsViewModel?.handle(
            .setDisplayCurrency(appState.primaryCurrencyCode)
        )
        financeDashboardDynamicsViewModel?.handle(.loadData)
    }

    private func openExpenseSheet() {
        prepareCashflowQuickAccess()
        showExpenseSheet = true
    }

    private func openIncomeSheet() {
        prepareCashflowQuickAccess()
        showIncomeSheet = true
    }

    private func openCashflowHistory() {
        prepareCashflowQuickAccess()
        showCashflowHistory = true
    }

    private func openFinanceAddProduct() {
        appState.pendingOpenFinanceAddCard = true
        router.navigationPath = NavigationPath()
        router.push(.finances)
    }
    
    @ViewBuilder
    private func routeView(for route: AppRoute) -> some View {
        switch route {
        case .finances:
            FinancesView()
        case .courses:
            CoursesView()
        case .cashback:
            CashbackView()
        case .cashflow:
            CashflowView()
        case .profile:
            ProfileView(router: router)
        case .subscription:
            SubscriptionView()
        default:
            EmptyView()
        }
    }
}

private struct ServiceReorderDropDelegate: DropDelegate {
    let targetService: ServiceItem
    @Binding var services: [ServiceItem]
    @Binding var draggedService: ServiceItem?
    let onReorderFinished: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedService, draggedService != targetService else { return }
        guard let fromIndex = services.firstIndex(of: draggedService),
              let toIndex = services.firstIndex(of: targetService) else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            services.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedService = nil
        onReorderFinished()
        return true
    }
}

#Preview {
    MainAppView(router: AppRouter())
        .environment(AppState())
}
