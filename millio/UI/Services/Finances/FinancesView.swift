//
//  FinancesView.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finances Tab Enum

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
        .interactiveBackSwipe()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    toolbarButtonLabel(systemName: "chevron.left", weight: .semibold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "finances.common.back"))
            }

            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(MiniAppNavigation.destinations(excluding: currentRoute)) { destination in
                        Button {
                            MiniAppNavigation.navigate(to: destination.route, from: currentRoute, router: router)
                        } label: {
                            Label(destination.title, systemImage: destination.systemImage)
                        }
                    }
                } label: {
                    toolbarButtonLabel(systemName: "square.grid.2x2", weight: .regular)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "finances.common.quick_navigation"))
            }

            if viewModel != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFinanceSettingsSheet = true
                    } label: {
                        toolbarButtonLabel(systemName: "gearshape", weight: .semibold)
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
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color.black.opacity(0.52), for: .tabBar)
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
    @State private var draggedGroupID: String?
    
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
                LazyVStack(spacing: FinancesMainLayoutPolicy.sectionSpacing) {
                    overviewHeroModule

                    if !visibleGroups.isEmpty {
                        overviewSnapshotSection
                    }

                    groupsListSection(visibleGroups)
                }
                .padding(.horizontal, FinancesMainLayoutPolicy.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, FinancesMainLayoutPolicy.scrollContentBottomPadding(showsAddFAB: showsAddFAB))
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
    
    // MARK: - Hero Overview Module

    private var overviewHeroModule: some View {
        VStack(alignment: .leading, spacing: 16) {
            totalAmountSection
        }
        .padding(22)
        .background(heroModuleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FinancesMainLayoutPolicy.heroCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: FinancesMainLayoutPolicy.heroCornerRadius, style: .continuous))
    }

    private var overviewSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FinanceOverviewCardView(
                financeViewModel: viewModel,
                chrome: .embedded
            )
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: FinancesMainLayoutPolicy.sectionCardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: FinancesMainLayoutPolicy.sectionCardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
    }
    
    // MARK: - Total Amount Section
    
    private var totalAmountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    headerActionButton(systemName: viewModel.state.isAmountHidden ? "eye.slash" : "eye") {
                        viewModel.handle(.toggleAmountVisibility)
                    }

                    refreshMenu
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
                .background(AppColors.warning.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.warning.opacity(0.32), lineWidth: 1)
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .frame(width: 32, height: 32)

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

    private func headerActionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var heroModuleBackground: some View {
        RoundedRectangle(cornerRadius: FinancesMainLayoutPolicy.heroCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.07),
                        Color.white.opacity(0.035),
                        Color.white.opacity(0.018)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill((AppColors.financesGradient.first ?? .cyan).opacity(0.08))
                    .blur(radius: 42)
                    .frame(width: 170, height: 170)
                    .offset(x: -48, y: -56)
            }
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppColors.brandPrimary.opacity(0.06)
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
    
    // MARK: - Groups List Section
    
    private func groupsListSection(_ visibleGroups: [FinanceGroup]) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            if visibleGroups.isEmpty {
                emptyGroupsCallToAction
            } else {
                Text("finances.main.accounts_section.title")
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
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.04, green: 0.08, blue: 0.12),
                                            Color(red: 0.02, green: 0.04, blue: 0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Circle()
                                        .stroke(AppColors.brandPrimary.opacity(0.34), lineWidth: 1)
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

private struct FinanceDynamicsTabView: View {
    @ObservedObject var financeViewModel: FinanceViewModel
    
    var body: some View {
        FinanceDynamicsView(
            financeViewModel: financeViewModel,
            wrapInNavigationStack: false
        )
    }
}
