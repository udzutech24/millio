//
//  FinancesView.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finances Tab Enum

struct FinancesEmptyStateIntroPrefs {
    static let hiddenKey = "finances_main_empty_intro_hidden"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isHidden() -> Bool {
        defaults.bool(forKey: Self.hiddenKey)
    }

    func setHidden(_ hidden: Bool) {
        defaults.set(hidden, forKey: Self.hiddenKey)
    }
}

enum FinancesTab: String {
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
    @State private var showFinanceSettingsSheet: Bool = false
    @State private var showBalanceAuditSheetFromSettings: Bool = false
    @State private var showMassTickerImportSheet: Bool = false
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
        .navigationTitle(String(localized: "finances.main.title"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 6) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.96))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "finances.common.back"))

                    Menu {
                        ForEach(MiniAppNavigation.destinations(excluding: currentRoute)) { destination in
                            Button {
                                MiniAppNavigation.navigate(to: destination.route, from: currentRoute, router: router)
                            } label: {
                                Label(destination.title, systemImage: destination.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.90))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "finances.common.quick_navigation"))
                }
            }

            if viewModel != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFinanceSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .accessibilityLabel(String(localized: "finances.common.settings"))
                }
            }
        }
        .sheet(isPresented: $showFinanceSettingsSheet) {
            if let viewModel {
                FinancesSettingsSheet(
                    onOpenSavingsGoal: {
                        showFinanceSettingsSheet = false
                        viewModel.handle(.showSavingsGoalSheet)
                    },
                    onOpenDailyAudit: {
                        showFinanceSettingsSheet = false
                        showBalanceAuditSheetFromSettings = true
                    },
                    onOpenMassTickerImport: {
                        showFinanceSettingsSheet = false
                        showMassTickerImportSheet = true
                    }
                )
            }
        }
        .sheet(isPresented: $showBalanceAuditSheetFromSettings) {
            if let viewModel {
                FinanceBalanceAuditSheet(
                    financeViewModel: viewModel,
                    modelContext: modelContext
                )
            }
        }
        .sheet(isPresented: $showMassTickerImportSheet) {
            if let viewModel {
                StockBulkImportSheet(
                    financeViewModel: viewModel,
                    modelContext: modelContext,
                    marketDataClient: viewModel.marketDataClient
                )
            }
        }
    }
}

// MARK: - Internal Content View

private struct FinancesContentViewInternal: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab: FinancesTab = .main
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Вкладка 1: Основной экран
            FinancesMainTabView(
                viewModel: viewModel
            )
                .tabItem {
                    Label("finances.main.title", systemImage: "creditcard")
                }
                .tag(FinancesTab.main)
            
            // Вкладка 2: Динамика
            FinanceDynamicsTabView(financeViewModel: viewModel)
                .tabItem {
                    Label("finances.dynamics.title", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(FinancesTab.dynamics)
        }
    }
}

private struct FinancesSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onOpenSavingsGoal: () -> Void
    let onOpenDailyAudit: () -> Void
    let onOpenMassTickerImport: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 12) {
                    Button {
                        onOpenMassTickerImport()
                    } label: {
                        settingsRow(
                            title: String(localized: "finances.settings.mass_import.title"),
                            subtitle: String(localized: "finances.settings.mass_import.subtitle"),
                            icon: "text.insert"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onOpenSavingsGoal()
                    } label: {
                        settingsRow(
                            title: String(localized: "finances.settings.savings_goal.title"),
                            subtitle: String(localized: "finances.settings.savings_goal.subtitle"),
                            icon: "target"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onOpenDailyAudit()
                    } label: {
                        settingsRow(
                            title: String(localized: "finances.settings.daily_audit.title"),
                            subtitle: String(localized: "finances.settings.daily_audit.subtitle"),
                            icon: "list.clipboard"
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .navigationTitle(String(localized: "finances.settings.title"))
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

#Preview {
    let schema = AppSchema.create()
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    
    FinancesView()
        .modelContainer(container)
        .environment(AppState())
}

// MARK: - Finances Main Tab View

private struct FinancesMainTabView: View {
    @ObservedObject var viewModel: FinanceViewModel
    
    var body: some View {
        mainContent
            .modifier(SheetsModifier(viewModel: viewModel))
    }
    
    private var mainContent: some View {
        ZStack {
            GradientBackground()
            
            let visibleGroups = viewModel.visibleGroupsForList()
            let showsAddFAB = FinancesMainLayoutPolicy.showsAddFAB(visibleGroupsCount: visibleGroups.count)

            ScrollView {
                VStack(spacing: 20) {
                    overviewHeroModule

                    // Список групп
                    groupsListSection(visibleGroups)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                // Отступ снизу оставляем только когда FAB реально отображается, чтобы пустой state не "падал" вниз.
                .padding(.bottom, FinancesMainLayoutPolicy.scrollContentBottomPadding(showsAddFAB: showsAddFAB))
            }

            if showsAddFAB {
                // Floating Action Button (FAB) внизу справа
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            viewModel.handle(.showAddAccountSheet(nil))
                        } label: {
                            let accentColor = AppColors.financesGradient.first ?? .cyan
                            let fillGradient = LinearGradient(
                                colors: [
                                    Color(red: 0.03, green: 0.07, blue: 0.11),
                                    Color(red: 0.02, green: 0.04, blue: 0.06),
                                    Color.black
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            let glowGradient = LinearGradient(
                                colors: [
                                    accentColor.opacity(0.18),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )

                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(fillGradient)
                                        .overlay(
                                            Circle()
                                                .fill(glowGradient)
                                                .opacity(0.6)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(accentColor.opacity(0.55), lineWidth: 1)
                                        )
                                )

                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }
    
    // MARK: - Hero Overview Module

    private var overviewHeroModule: some View {
        VStack(alignment: .leading, spacing: 18) {
            totalAmountSection

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.02),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            FinanceOverviewCardView(
                financeViewModel: viewModel,
                chrome: .embedded
            )
        }
        .padding(20)
        .background(heroModuleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    
    // MARK: - Total Amount Section
    
    private var totalAmountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatBalance(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Button {
                        viewModel.handle(.showDisplayCurrencySheet)
                    } label: {
                        Text(MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        viewModel.handle(.toggleAmountVisibility)
                    } label: {
                        Image(systemName: viewModel.state.isAmountHidden ? "eye.slash" : "eye")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    refreshMenu
                }
            }

            if let secondaryCurrency = viewModel.state.secondaryDisplayCurrency {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatBalance(viewModel.state.secondaryTotalAmount, isHidden: viewModel.state.isAmountHidden))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)

                    Button {
                        viewModel.handle(.showSecondaryDisplayCurrencySheet)
                    } label: {
                        Text(MonetaCurrency(rawValue: secondaryCurrency)?.symbol ?? secondaryCurrency)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let warning = viewModel.state.currencyConversionWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.warning)

                    Text("finances.main.warning.currency_api_partial")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.warning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.warning.opacity(0.4), lineWidth: 1)
                }
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
                            .foregroundStyle(AppColors.financesGradient.first ?? AppColors.brandPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Spacer()
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                .padding(.top, 4)
            }
            
            if viewModel.state.isLoadingRates {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var refreshMenu: some View {
        Menu {
            Button("finances.main.refresh_quotes") {
                Task {
                    await viewModel.refreshCurrencyQuotes()
                }
            }
            .disabled(viewModel.state.isLoadingRates)

            Button("finances.main.refresh_stocks") {
                Task {
                    await viewModel.refreshStockPrices()
                }
            }
            .disabled(viewModel.state.isLoadingRates)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: 26, height: 26)

                if viewModel.state.isLoadingRates {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColors.textSecondary)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .accessibilityLabel(viewModel.state.isLoadingRates
            ? String(localized: "finances.common.refreshing")
            : String(localized: "finances.common.refresh"))
    }

    private var heroModuleBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.04),
                        Color.white.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill((AppColors.financesGradient.first ?? .cyan).opacity(0.10))
                    .blur(radius: 30)
                    .frame(width: 180, height: 180)
                    .offset(x: -40, y: -50)
            }
    }
    
    // MARK: - Groups List Section
    
    private func groupsListSection(_ visibleGroups: [FinanceGroup]) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            if visibleGroups.isEmpty {
                emptyGroupsCallToAction
            } else {
                Text("finances.main.accounts_section.title")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.90))
                    .accessibilityAddTraits(.isHeader)

                groupsListView(visibleGroups)
            }
        }
    }

    private func groupsListView(_ groups: [FinanceGroup]) -> some View {
        VStack(spacing: 12) {
            ForEach(groups) { group in
                FinanceGroupRow(
                    group: group,
                    viewModel: viewModel
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
    
    private func goalProgressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * progress))
            }
        }
        .frame(height: 10)
    }

    private var emptyGroupsCallToAction: some View {
        VStack(spacing: 14) {
            Button {
                viewModel.handle(.showAddAccountSheet(nil))
            } label: {
                Text("finances.main.empty_intro.add_product")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}

// MARK: - Finance Dynamics Tab View

private struct FinanceDynamicsTabView: View {
    @ObservedObject var financeViewModel: FinanceViewModel
    
    var body: some View {
        FinanceDynamicsView(
            financeViewModel: financeViewModel,
            wrapInNavigationStack: false
        )
    }
}
