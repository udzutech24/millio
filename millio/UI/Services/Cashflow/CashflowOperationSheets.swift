//
//  CashflowOperationSheets.swift
//  millio
//
//  Created by Codex on 01.03.2026.
//

import SwiftUI
import UIKit

enum CashflowOperationSheetLayoutPolicy {
    static let floatingAddCategoryButtonSize: CGFloat = 64
    static let floatingAddCategoryBottomPadding: CGFloat = 20

    static func scrollContentBottomPadding() -> CGFloat {
        BottomPinnedLayoutPolicy.scrollContentBottomPaddingForOverlay(
            overlayHeight: floatingAddCategoryButtonSize,
            overlayBottomPadding: floatingAddCategoryBottomPadding
        )
    }
}

enum CashflowCategorySheetBootstrap {
    @MainActor
    static func prepare(viewModel: CashflowViewModel) {
        viewModel.handle(.loadCards)
        viewModel.handle(.loadTransactions)
    }

    /// Builds the default transaction date for category-driven creation flows.
    /// We keep the current day-of-month when possible, but always clamp the
    /// result into the month currently selected in the category sheet.
    nonisolated static func initialTransactionDate(
        forSelectedMonth selectedMonth: Date,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: selectedMonth)
        ) ?? selectedMonth
        let referenceComponents = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: referenceDate
        )
        let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        let clampedDay = min(max(calendar.component(.day, from: referenceDate), 1), maxDay)

        var components = calendar.dateComponents([.year, .month], from: monthStart)
        components.day = clampedDay
        components.hour = referenceComponents.hour
        components.minute = referenceComponents.minute
        components.second = referenceComponents.second
        components.nanosecond = referenceComponents.nanosecond

        return calendar.date(from: components) ?? monthStart
    }
}
struct CashflowIncomeTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let initialHistoryCardID: String?

    init(viewModel: CashflowViewModel, initialHistoryCardID: String? = nil) {
        self.viewModel = viewModel
        self.initialHistoryCardID = initialHistoryCardID
    }

    var body: some View {
        CashflowCategoryTransactionSheet(
            viewModel: viewModel,
            kind: .income,
            initialHistoryCardID: initialHistoryCardID
        )
    }
}

struct CashflowExpenseTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let initialHistoryCardID: String?

    init(viewModel: CashflowViewModel, initialHistoryCardID: String? = nil) {
        self.viewModel = viewModel
        self.initialHistoryCardID = initialHistoryCardID
    }

    var body: some View {
        CashflowCategoryTransactionSheet(
            viewModel: viewModel,
            kind: .expense,
            initialHistoryCardID: initialHistoryCardID
        )
    }
}

struct CashflowCategoryTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryTransactionSheetKind
    let initialHistoryCardID: String?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedCategory: CashflowCategoryOption?
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    @State private var monthlyTotal: Double = 0
    @State private var categoryTotals: [String: Double] = [:]
    @State private var budgetSnapshot: BudgetProgressSnapshot?
    @State private var categoryBudgetLimits: [String: Double] = [:]
    @State private var budgetTotalLimit: Double?
    @State private var lastBudgetHapticStep: Int = -1
    @State private var lastCategoryBudgetSteps: [String: Int] = [:]
    @State private var isLoadingMonthlyTotal: Bool = false
    @State private var monthTotalTask: Task<Void, Never>?
    @State private var showRecurringManagement: Bool = false
    @State private var showPlannedManagement: Bool = false
    @State private var showTransactionsHistory: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var showBulkExpenseImportSheet: Bool = false
    @State private var showBudgetSetupSheet: Bool = false

    @State private var showCreateCategorySheet: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryIcon: String = CashflowCustomCategory.defaultIcon
    @State private var showCategoryEditorSheet: Bool = false
    @State private var showCategoryActionsDialog: Bool = false
    @State private var categoryEditorMode: CashflowCategoryEditorMode = .create
    @State private var categoryEditorName: String = ""
    @State private var categoryEditorIcon: String = CashflowCustomCategory.defaultIcon
    @State private var pendingCategoryDeletionPreview: CashflowCategoryDeletionPreview?
    @State private var pendingCategoryUndoAction: CashflowCategoryMutationUndoAction?
    @State private var categoryUndoDismissTask: Task<Void, Never>?
    @State private var pendingActionCategory: CashflowCategoryOption?
    @State private var categoryGridWidth: CGFloat = UIScreen.main.bounds.width
    @State private var highlightedCategoryRaw: String?
    @State private var categoryUpdateFeedbackPlan: CashflowCategoryUpdateFeedbackPlan?
    @State private var categoryFeedbackSequence: Int = 0
    @State private var hasCompletedInitialLoad: Bool = false
    @State private var suppressNextCategoryTap: Bool = false
    @State private var showReorderSheet: Bool = false
    @State private var quickEntryCategory: CashflowCategoryOption?
    @FocusState private var isSearchFieldFocused: Bool
    private let outerCornerRadius: CGFloat = 22
    private let innerCornerRadius: CGFloat = 16

    private var showsBudgetDetails: Bool {
        budgetSnapshot != nil
    }

    private var categoryColumns: [GridItem] {
        CashflowCategoryGridLayout.columns(
            for: kind,
            containerWidth: categoryGridWidth,
            showsBudgetDetails: showsBudgetDetails
        )
    }

    private var currentMonthStart: Date {
        Calendar.current.startOfMonth(for: Date())
    }

    private var canMoveForward: Bool {
        selectedMonth < currentMonthStart
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: selectedMonth).localizedCapitalized
    }

    private var categories: [CashflowCategoryOption] {
        viewModel.orderedCategoryOptions(
            for: kind.categoryKind,
            matching: searchText,
            totalsByCategory: categoryTotals
        )
    }

    private var planButtonTitle: String {
        CashflowBudgetLocalization.planButtonTitle(for: kind, hasBudget: budgetSnapshot != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            headerSection
                            monthlyTotalSection
                            managementSection
                            categoriesSectionHeader
                            categoriesSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, CashflowOperationSheetLayoutPolicy.scrollContentBottomPadding())
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .dismissKeyboardOnTap()
                    .onChange(of: categoryFeedbackSequence) { _, _ in
                        presentCategoryUpdateFeedback(using: scrollProxy)
                    }

                    floatingAddCategoryButton
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedCategory) { option in
                CashflowTransactionEditorView(
                    viewModel: viewModel,
                    transactionType: kind.transactionType,
                    showsTransactionTypeSection: false,
                    showsCategorySection: false,
                    wrapsInNavigationStack: false,
                    showsDismissButton: false,
                    customNavigationTitle: kind.navigationTitle,
                    preselectedIncomeCategoryRaw: kind.categoryKind == .income ? option.rawValue : nil,
                    preselectedExpenseCategoryRaw: kind.categoryKind == .expense ? option.rawValue : nil,
                    initialTransactionDate: CashflowCategorySheetBootstrap.initialTransactionDate(
                        forSelectedMonth: selectedMonth
                    ),
                    onSave: {
                        selectedCategory = nil
                        reloadMonthlyTotal(focusingOn: option.rawValue)
                    }
                )
            }
            .navigationDestination(isPresented: $showTransactionsHistory) {
                CashflowTransactionsHistoryView(
                    viewModel: viewModel,
                    showsDismissButton: false,
                    initialFilter: kind.historyFilter,
                    initialCategoryRawValue: pendingActionCategory?.rawValue,
                    initialCardID: initialHistoryCardID,
                    initialStartDate: historyRange.start,
                    initialEndDate: historyRange.end
                )
            }
            .sheet(isPresented: $showRecurringManagement) {
                scheduledManagementSheet(mode: .recurring)
            }
            .sheet(isPresented: $showPlannedManagement) {
                scheduledManagementSheet(mode: .planner)
            }
            .sheet(isPresented: $showCreateCategorySheet) {
                CashflowCategoryQuickCreateSheet(
                    name: $newCategoryName,
                    icon: $newCategoryIcon,
                    onSave: handleCreateCategory
                )
            }
            .sheet(isPresented: $showSettingsSheet) {
                CashflowCategorySettingsSheet(viewModel: viewModel, kind: kind)
            }
            .sheet(isPresented: $showBulkExpenseImportSheet) {
                CashflowBulkExpenseImportSheet(
                    viewModel: viewModel,
                    month: selectedMonth,
                    onComplete: {
                        reloadMonthlyTotal()
                    }
                )
            }
            .sheet(isPresented: $showBudgetSetupSheet) {
                let repeatSuggestion = viewModel.previousMonthlyBudgetSuggestion(
                    for: selectedMonth,
                    categoryKind: kind.categoryKind
                )
                BudgetSetupSheet(
                    categoryKind: kind.categoryKind,
                    periodTitle: monthTitle,
                    currencyCode: cashflowCurrencyCodeLabel(viewModel.state.displayCurrency),
                    existingAmount: budgetTotalLimit,
                    categoryOptions: viewModel.categoryOptions(for: kind.categoryKind),
                    existingCategoryLimits: categoryBudgetLimits,
                    categorySnapshots: budgetSnapshot?.categorySnapshots ?? [],
                    repeatSuggestion: repeatSuggestion,
                    isAutoRepeatEnabled: viewModel.isMonthlyBudgetAutoRepeatEnabled,
                    onSave: { amount, limits in
                        viewModel.saveMonthlyBudgetConfiguration(
                            categoryKind: kind.categoryKind,
                            month: selectedMonth,
                            totalAmount: amount,
                            categoryLimits: limits,
                            currency: viewModel.state.displayCurrency
                        )
                        reloadMonthlyTotal()
                    },
                    onAutoRepeatChanged: { isEnabled in
                        viewModel.isMonthlyBudgetAutoRepeatEnabled = isEnabled
                    }
                )
            }
            .fullScreenCover(isPresented: $showCategoryEditorSheet) {
                CashflowCategoryEditorSheet(
                    mode: categoryEditorMode,
                    name: $categoryEditorName,
                    icon: $categoryEditorIcon
                ) { name, icon in
                    handleCategoryEditorSave(name: name, icon: icon)
                }
            }
            .overlay(alignment: .bottom) {
                if let option = pendingActionCategory {
                    CashflowCategoryActionOverlay(
                        isPresented: showCategoryActionsDialog,
                        categoryName: option.displayName,
                        categoryIcon: option.icon,
                        accentColor: kind.accentColor,
                        primaryActionTitle: viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)
                            ? L("cashflow.category.actions.unpin")
                            : L("cashflow.category.actions.pin"),
                        primaryActionIcon: viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)
                            ? "pin.slash"
                            : "pin",
                        onPrimaryAction: {
                            togglePinned(for: option)
                            closeCategoryActions()
                        },
                        secondaryActionTitle: L("cashflow.category.actions.operations"),
                        secondaryActionIcon: "list.bullet.rectangle",
                        onSecondaryAction: {
                            openOperations(for: option)
                        },
                        onEdit: {
                            closeCategoryActions()
                            openCategoryEditor(for: option)
                        },
                        deleteActionTitle: destructiveActionTitle(for: option),
                        deleteActionIcon: destructiveActionIcon(for: option),
                        onDelete: viewModel.canDeleteCategory(rawValue: option.rawValue, kind: kind.categoryKind) ? {
                            closeCategoryActions()
                            presentDeleteCategoryFlow(for: option)
                        } : nil,
                        onDismiss: closeCategoryActions
                    )
                }
            }
            .sheet(item: $pendingCategoryDeletionPreview) { preview in
                CashflowCategoryDeletionSheet(viewModel: viewModel, preview: preview) { targetRaw in
                    handleCategoryDeletion(preview: preview, targetRaw: targetRaw)
                }
            }
            .sheet(item: $quickEntryCategory) { option in
                CashflowQuickEntrySheet(
                    viewModel: viewModel,
                    option: option,
                    kind: kind,
                    selectedMonth: selectedMonth,
                    onSave: {
                        reloadMonthlyTotal(focusingOn: option.rawValue)
                    },
                    onOpenFullEditor: { category in
                        // Небольшая задержка чтобы quick sheet успел закрыться
                        // перед тем как navigationDestination сработает
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            selectedCategory = category
                        }
                    }
                )
            }
            .overlay(alignment: .bottom) {
                if let pendingCategoryUndoAction {
                    CashflowCategoryUndoBanner(action: pendingCategoryUndoAction) {
                        handleUndoCategoryDeletion()
                    } onDismiss: {
                        dismissUndoCategoryDeletion()
                    }
                }
            }
            .onAppear {
                CashflowCategorySheetBootstrap.prepare(viewModel: viewModel)
                reloadMonthlyTotal()
            }
            .onChange(of: selectedMonth) { _, _ in
                reloadMonthlyTotal()
            }
            .onDisappear {
                monthTotalTask?.cancel()
                monthTotalTask = nil
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            circleToolbarButton(systemName: "xmark", accessibilityLabel: L("cashflow.common.close")) {
                dismiss()
            }

            HStack(spacing: 10) {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                        .frame(width: 24, height: 24)
                        .background(monthChevronBackground)
                }
                .buttonStyle(.plain)

                Text(monthTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                .frame(maxWidth: .infinity)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canMoveForward ? AppColors.textPrimary.opacity(0.9) : AppColors.textSecondary.opacity(0.45))
                        .frame(width: 24, height: 24)
                        .background(monthChevronBackground)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(monthHeaderBackground)

            HStack(spacing: 8) {
                circleToolbarButton(
                    systemName: "clock.arrow.circlepath",
                    accessibilityLabel: L("cashflow.operation.history_accessibility")
                ) {
                    showTransactionsHistory = true
                }

                circleToolbarButton(
                    systemName: "gearshape",
                    accessibilityLabel: L("cashflow.common.settings")
                ) {
                    showSettingsSheet = true
                }
            }
        }
        .padding(.top, 6)
    }

    private var monthlyTotalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.monthlyTotalTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button {
                    showBudgetSetupSheet = true
                } label: {
                    Text(planButtonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(innerPanelBackground)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            monthlySummaryHeroSection
        }
        .padding(12)
        .background(outerPanelBackground)
    }

    @ViewBuilder
    private var monthlySummaryHeroSection: some View {
        let chartEntries = heroChartEntries
        let showChart = !chartEntries.isEmpty

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                if isLoadingMonthlyTotal {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                        .scaleEffect(0.9)
                        .padding(.vertical, 10)
                } else {
                    Text(formattedMonthlyTotal(monthlyTotal))
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText())
                        .shadow(color: kind.accentColor.opacity(0.45), radius: 12, x: 0, y: 0)
                }

                monthlyBudgetInlineSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showChart {
                Button {
                    showTransactionsHistory = true
                } label: {
                    CashflowHistoryRingChart(
                        entries: chartEntries,
                        selectedRawValue: nil,
                        progress: 0,
                        onSelect: { _ in }
                    )
                    .frame(width: 80, height: 80)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(heroCardBackground)
    }

    private var heroChartEntries: [CashflowHistorySummaryEntry] {
        let palette: [String] = kind == .expense
            ? ["47D7FF", "FF9F5A", "F68BA7", "6FD2A8", "AFC8FF", "C5B6FF", "E7C66C", "9EA7BC"]
            : ["63E6BE", "47D7FF", "7AB6FF", "FFD166", "FF9B9B", "D0BFFF", "95E0A3", "A1A7B8"]
        let filtered = categoryTotals.filter { $0.value > 0.0000001 }
        let total = filtered.values.reduce(0, +)
        guard total > 0 else { return [] }
        let optionMap = Dictionary(uniqueKeysWithValues: viewModel.categoryOptions(for: kind.categoryKind).map { ($0.rawValue, $0) })
        return filtered
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { index, item in
                let option = optionMap[item.key]
                return CashflowHistorySummaryEntry(
                    rawValue: item.key,
                    title: option?.displayName ?? item.key,
                    icon: option?.icon ?? "questionmark",
                    amount: item.value,
                    share: item.value / total,
                    tintHex: palette[index % palette.count]
                )
            }
    }

    private var heroCardBackground: some View {
        RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [kind.accentColor.opacity(0.38), Color.black.opacity(0.36)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .stroke(kind.strokeGradient.opacity(0.60), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var monthlyBudgetInlineSection: some View {
        if let snapshot = budgetSnapshot {
            let style = budgetMonthlySummaryStyle(kind: kind, snapshot: snapshot)
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { proxy in
                    let progress = min(max(snapshot.progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        Capsule(style: .continuous)
                            .fill(kind.strokeGradient)
                            .frame(width: max(12, proxy.size.width * progress))
                    }
                }
                .frame(height: 10)

                if snapshot.categoriesLimitOverflow > 0.0000001 {
                    Text(CashflowBudgetLocalization.monthlyOverflow(
                        for: kind,
                        amount: formattedAmount(snapshot.categoriesLimitOverflow)
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(style.usageText.color)
                }
            }
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let entries = CashflowManagementEntry.entries(for: kind.categoryKind)
            HStack(spacing: 10) {
                ForEach(entries) { entry in
                    managementButton(entry: entry)
                }

                searchToggleButton
            }

            if shouldShowSearchField {
                searchSection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: shouldShowSearchField)
    }

    private func managementButton(entry: CashflowManagementEntry) -> some View {
        Button {
            handleManagementTap(entry)
        } label: {
            Image(systemName: entry.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(maxWidth: .infinity, minHeight: 52)
            .background(innerPanelBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.title)
    }

    private var searchToggleButton: some View {
        Button {
            toggleSearch()
        } label: {
            Image(systemName: shouldShowSearchField ? "xmark" : "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(maxWidth: .infinity, minHeight: 52)
            .background(innerPanelBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            shouldShowSearchField
            ? L("cashflow.common.close", defaultValue: "Close")
            : L("cashflow.operation.search_category", defaultValue: "Search category")
        )
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            TextField(L("cashflow.operation.search_category"), text: $searchText)
                .textInputAutocapitalization(.words)
                .foregroundStyle(AppColors.textPrimary)
                .focused($isSearchFieldFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(innerPanelBackground)
        .onChange(of: isSearchFieldFocused) { _, isFocused in
            guard !isFocused, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            isSearchExpanded = false
        }
    }

    private var shouldShowSearchField: Bool {
        isSearchExpanded || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleSearch() {
        if shouldShowSearchField {
            searchText = ""
            isSearchExpanded = false
            isSearchFieldFocused = false
        } else {
            isSearchExpanded = true
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private func handleManagementTap(_ entry: CashflowManagementEntry) {
        switch entry.destination {
        case .bulkImport:
            showBulkExpenseImportSheet = true
        case .recurring:
            showRecurringManagement = true
        case .planned:
            showPlannedManagement = true
        }
    }

    @ViewBuilder
    private func scheduledManagementSheet(mode: CashflowScheduledTransactionsMode) -> some View {
        NavigationStack {
            CashflowScheduledTransactionsView(
                viewModel: viewModel,
                kind: kind.categoryKind,
                mode: mode
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if mode == .recurring {
                            showRecurringManagement = false
                        } else {
                            showPlannedManagement = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("cashflow.common.close"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var hasCustomCategoryOrder: Bool {
        viewModel.categoryCustomOrder(for: kind.categoryKind) != nil
    }

    private var categoriesSectionHeader: some View {
        HStack {
            Spacer()
            Button {
                showReorderSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                    Text(
                        hasCustomCategoryOrder
                        ? L("cashflow.category.reorder.edit", defaultValue: "Edit order")
                        : L("cashflow.category.reorder.sort", defaultValue: "Sort")
                    )
                    .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(
                    hasCustomCategoryOrder
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(AppColors.textSecondary)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showReorderSheet) {
                CashflowCategoryReorderSheet(viewModel: viewModel, kind: kind.categoryKind)
            }
        }
    }

    private var categoriesSection: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: categoryColumns, spacing: 10) {
                ForEach(categories) { option in
                    categoryCard(for: option)
                        .id(option.rawValue)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateCategoryGridWidth(proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            updateCategoryGridWidth(newWidth)
                        }
                }
            }

            if hasCompletedInitialLoad && monthlyTotal == 0 {
                cashflowEmptyMonthState
                    .padding(.top, 24)
            }
        }
    }

    private var cashflowEmptyMonthState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(L("cashflow.category.empty_month"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    private func categoryCard(for option: CashflowCategoryOption) -> some View {
        let summary = categoryBudgetSummary(for: option)
        let cardHasBudgetDetails = summary != nil
        let metrics = CashflowCategoryGridLayout.cardMetrics(
            showsBudgetDetails: cardHasBudgetDetails
        )
        let isHighlighted = highlightedCategoryRaw == option.rawValue
        let feedbackPlan = categoryUpdateFeedbackPlan?.categoryRawValue == option.rawValue ? categoryUpdateFeedbackPlan : nil
        let feedbackColor = kind.amountColor(for: feedbackPlan?.delta ?? 0)
        let isPinned = viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)
        let pinAffordanceStyle = CashflowCategoryGridLayout.pinAffordanceStyle(
            for: kind,
            isPinned: isPinned
        )
        let pinPlacement = CashflowCategoryGridLayout.pinPlacement(for: pinAffordanceStyle)

        return ZStack(alignment: .topTrailing) {
            Button {
                if suppressNextCategoryTap {
                    suppressNextCategoryTap = false
                    return
                }
                quickEntryCategory = option
            } label: {
                VStack(alignment: .leading, spacing: metrics.contentSpacing) {
                    HStack(alignment: .top) {
                        ZStack {
                            Circle()
                                .fill(kind.accentColor.opacity(0.18))
                                .overlay(
                                    Circle()
                                        .stroke(kind.accentColor.opacity(0.35), lineWidth: 1)
                                )
                            CashflowCategoryIconView(
                                icon: option.icon,
                                fontSize: 20,
                                fontWeight: .semibold,
                                tint: AnyShapeStyle(AppColors.textPrimary)
                            )
                        }
                        .frame(width: 38, height: 38)
                        Spacer(minLength: 6)

                        HStack(spacing: 6) {
                            if let summary, let badge = categoryBudgetBadgeText(summary.status) {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .foregroundStyle(budgetStatusColor(summary.status))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(budgetStatusColor(summary.status).opacity(0.14))
                                    )
                            }

                            if pinPlacement == .inlineBadge {
                                pinnedBadge
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: metrics.topRowMinHeight, alignment: .topLeading)

                    Text(option.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, minHeight: metrics.titleMinHeight, alignment: .topLeading)

                    if metrics.usesFlexibleSpacer {
                        Spacer(minLength: 0)
                    }

                    Text(formattedCategoryTotal(for: option))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle((summary == nil ? AppColors.textSecondary : AppColors.textPrimary).opacity(0.98))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, metrics.amountTopPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                        .scaleEffect(isHighlighted ? 1.07 : 1)
                        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isHighlighted)

                    if let feedbackPlan, isHighlighted {
                        Text(cashflowSignedAmountText(feedbackPlan.delta))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(feedbackColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(feedbackColor.opacity(0.55), lineWidth: 1)
                                    )
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }

                    Group {
                        if let summary {
                            VStack(alignment: .leading, spacing: metrics.contentSpacing) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(categoryBudgetLimitLabel(summary.limit))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(0.66))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                }

                                GeometryReader { proxy in
                                    let progress = min(max(summary.progress, 0), 1)
                                    ZStack(alignment: .leading) {
                                        Capsule(style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                        Capsule(style: .continuous)
                                            .fill(budgetStatusColor(summary.status))
                                            .frame(width: max(8, proxy.size.width * progress))
                                    }
                                }
                                .frame(height: 6)
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: metrics.footerMinHeight, alignment: .bottomLeading)
                }
                .frame(maxWidth: .infinity, minHeight: metrics.cardMinHeight, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, metrics.verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(categoryStrokeStyle(for: option), lineWidth: 1.1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(feedbackColor.opacity(isHighlighted ? 0.95 : 0), lineWidth: 1.4)
                        )
                        .shadow(color: feedbackColor.opacity(isHighlighted ? 0.28 : 0), radius: isHighlighted ? 16 : 0)
                )
                .scaleEffect(isHighlighted ? 1.015 : 1)
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: isHighlighted)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        suppressNextCategoryTap = true
                        openCategoryActions(for: option)
                    }
            )

            switch pinAffordanceStyle {
            case .hidden:
                EmptyView()
            case .compactBadge:
                EmptyView()
            case .regularButton:
                Button {
                    togglePinned(for: option)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPinned ? Color.black : AppColors.textPrimary.opacity(0.82))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isPinned ? Color(hex: "FF6B6B") : Color.white.opacity(0.08))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(isPinned ? 0.0 : 0.10), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(
                    isPinned
                        ? L("cashflow.category.actions.unpin")
                        : L("cashflow.category.actions.pin")
                )
            }
        }
    }

    private var pinnedBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color(hex: "FF6B6B"))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .accessibilityLabel(L("cashflow.category.pinned"))
    }

    private var floatingAddCategoryButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showCreateCategorySheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(
                            width: CashflowOperationSheetLayoutPolicy.floatingAddCategoryButtonSize,
                            height: CashflowOperationSheetLayoutPolicy.floatingAddCategoryButtonSize
                        )
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.92))
                                .overlay(
                                    Circle()
                                        .stroke(kind.strokeGradient.opacity(0.72), lineWidth: 1.4)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var outerPanelBackground: some View {
        RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.24))
            .overlay(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .stroke(kind.strokeGradient.opacity(0.76), lineWidth: 1)
            )
    }

    private var innerPanelBackground: some View {
        RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.30))
            .overlay(
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }

    private var toolbarCircleBackground: some View {
        Circle()
            .fill(Color.black.opacity(0.92))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.78), lineWidth: 1.6)
            )
    }

    private var monthChevronBackground: some View {
        Circle()
            .fill(Color.white.opacity(0.04))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private var monthHeaderBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.black.opacity(0.24))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func circleToolbarButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func shiftMonth(by value: Int) {
        let calendar = Calendar.current
        guard let newValue = calendar.date(byAdding: .month, value: value, to: selectedMonth) else {
            return
        }

        let normalized = calendar.startOfMonth(for: newValue)
        if normalized > currentMonthStart {
            selectedMonth = currentMonthStart
        } else {
            selectedMonth = normalized
        }
    }

    private var historyRange: (start: Date, end: Date) {
        CashflowViewModel.monthHistoryRange(for: selectedMonth, calendar: .current)
    }

    private func openOperations(for option: CashflowCategoryOption) {
        pendingActionCategory = option
        showCategoryActionsDialog = false
        showTransactionsHistory = true
    }

    private func reloadMonthlyTotal(focusingOn categoryRawValue: String? = nil) {
        monthTotalTask?.cancel()
        monthTotalTask = Task {
            await MainActor.run {
                isLoadingMonthlyTotal = true
            }

            let total: Double
            switch kind {
            case .income:
                total = await viewModel.monthlyIncomeTotal(for: selectedMonth, in: viewModel.state.displayCurrency)
            case .expense:
                total = await viewModel.monthlyExpenseTotal(for: selectedMonth, in: viewModel.state.displayCurrency)
            }
            let totalsByCategory = await viewModel.monthlyCategoryTotals(
                for: kind.categoryKind,
                month: selectedMonth,
                in: viewModel.state.displayCurrency
            )
            let budgetSummary = await viewModel.monthlyBudgetSummary(
                for: kind.categoryKind,
                month: selectedMonth,
                in: viewModel.state.displayCurrency
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                let previousCategoryTotals = categoryTotals
                let previousBudgetSnapshot = budgetSnapshot
                let previousCategorySteps = lastCategoryBudgetSteps
                let shouldAnimateValueUpdate = hasCompletedInitialLoad || categoryRawValue != nil
                let feedbackPlan = CashflowCategoryUpdateFeedbackPlan.make(
                    for: categoryRawValue,
                    previousTotals: previousCategoryTotals,
                    updatedTotals: totalsByCategory
                )

                let applyStateUpdate = {
                    monthlyTotal = total
                    categoryTotals = totalsByCategory
                    budgetSnapshot = budgetSummary.snapshot
                    categoryBudgetLimits = budgetSummary.categoryLimits
                    budgetTotalLimit = budgetSummary.plan?.totalLimitAmount
                    isLoadingMonthlyTotal = false
                    categoryUpdateFeedbackPlan = feedbackPlan
                }

                if shouldAnimateValueUpdate {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        applyStateUpdate()
                    }
                } else {
                    applyStateUpdate()
                }

                if feedbackPlan != nil {
                    categoryFeedbackSequence += 1
                } else {
                    highlightedCategoryRaw = nil
                    categoryUpdateFeedbackPlan = nil
                }

                hasCompletedInitialLoad = true

                handleBudgetThresholdHaptics(
                    previousSnapshot: previousBudgetSnapshot,
                    newSnapshot: budgetSummary.snapshot,
                    previousCategorySteps: previousCategorySteps
                )
            }
        }
    }

    private func presentCategoryUpdateFeedback(using scrollProxy: ScrollViewProxy) {
        guard let feedbackPlan = categoryUpdateFeedbackPlan else { return }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            scrollProxy.scrollTo(feedbackPlan.categoryRawValue, anchor: .center)
            highlightedCategoryRaw = feedbackPlan.categoryRawValue
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                guard highlightedCategoryRaw == feedbackPlan.categoryRawValue else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    highlightedCategoryRaw = nil
                }
            }
        }
    }

    private func formattedCategoryTotal(for option: CashflowCategoryOption) -> String {
        let value = categoryTotals[option.rawValue] ?? 0
        return formattedAmount(value)
    }

    private func categoryBudgetSummary(for option: CashflowCategoryOption) -> BudgetCategoryProgressSnapshot? {
        return budgetSnapshot?.categorySnapshots.first(where: { $0.categoryRawValue == option.rawValue })
    }

    private func formattedAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: value)) ?? "0"
        return amount
    }

    private func categoryBudgetLimitLabel(_ value: Double) -> String {
        CashflowBudgetLocalization.categoryBudgetLimitLabel(
            for: kind.categoryKind,
            amount: formattedAmount(value)
        )
    }

    private func handleCreateCategory(_ name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if viewModel.createCustomCategory(kind: kind.categoryKind, name: trimmedName, icon: icon) != nil {
            searchText = ""
        }

        newCategoryName = ""
        newCategoryIcon = CashflowCustomCategory.defaultIcon
        showCreateCategorySheet = false
    }

    private func togglePinned(for option: CashflowCategoryOption) {
        let nextValue = !viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)
        viewModel.setCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind, isPinned: nextValue)
    }

    private func openCategoryEditor(for option: CashflowCategoryOption) {
        categoryEditorMode = .edit(rawValue: option.rawValue)
        categoryEditorName = option.displayName
        categoryEditorIcon = option.icon
        showCategoryEditorSheet = true
    }

    private func openCategoryActions(for option: CashflowCategoryOption) {
        pendingActionCategory = option
        showCategoryActionsDialog = true
    }

    private func closeCategoryActions() {
        showCategoryActionsDialog = false
        pendingActionCategory = nil
    }

    private func destructiveActionTitle(for option: CashflowCategoryOption) -> String {
        option.isCustom
            ? L("cashflow.category.actions.delete")
            : String(
                localized: "cashflow.category.actions.archive",
                defaultValue: "Archive",
                comment: "Archive system category action title"
            )
    }

    private func destructiveActionIcon(for option: CashflowCategoryOption) -> String {
        option.isCustom ? "trash" : "archivebox"
    }

    private func presentDeleteCategoryFlow(for option: CashflowCategoryOption) {
        pendingCategoryDeletionPreview = viewModel.categoryDeletionPreview(
            rawValue: option.rawValue,
            kind: kind.categoryKind
        )
    }

    private func handleCategoryDeletion(preview: CashflowCategoryDeletionPreview, targetRaw: String) {
        guard let undoAction = viewModel.performCategoryRemoval(
            rawValue: preview.rawValue,
            kind: preview.kind,
            targetRawValue: targetRaw
        ) else {
            return
        }

        if selectedCategory?.rawValue == preview.rawValue {
            selectedCategory = viewModel.categoryOption(for: targetRaw, kind: preview.kind)
        }
        pendingCategoryDeletionPreview = nil
        presentUndoCategoryDeletion(undoAction)
    }

    private func presentUndoCategoryDeletion(_ action: CashflowCategoryMutationUndoAction) {
        categoryUndoDismissTask?.cancel()
        pendingCategoryUndoAction = action
        categoryUndoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            pendingCategoryUndoAction = nil
        }
    }

    private func dismissUndoCategoryDeletion() {
        categoryUndoDismissTask?.cancel()
        categoryUndoDismissTask = nil
        pendingCategoryUndoAction = nil
    }

    private func handleUndoCategoryDeletion() {
        guard let action = pendingCategoryUndoAction else { return }
        guard viewModel.undoCategoryMutation(action) else { return }
        if selectedCategory?.rawValue == action.targetOption.rawValue {
            selectedCategory = viewModel.categoryOption(
                for: action.sourceOption.rawValue,
                kind: action.kind
            )
        }
        dismissUndoCategoryDeletion()
    }

    private func handleCategoryEditorSave(name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        switch categoryEditorMode {
        case .create:
            if viewModel.createCustomCategory(kind: kind.categoryKind, name: trimmedName, icon: icon) != nil {
                searchText = ""
            }
        case .edit(let rawValue):
            guard viewModel.renameCategory(
                rawValue: rawValue,
                kind: kind.categoryKind,
                newName: trimmedName,
                newIcon: icon
            ) else { return }

            if selectedCategory?.rawValue == rawValue {
                if let resolved = viewModel.categoryOptions(for: kind.categoryKind, includeHiddenSystem: true).first(where: {
                    $0.displayName.caseInsensitiveCompare(trimmedName) == .orderedSame
                }) {
                    selectedCategory = resolved
                } else {
                    selectedCategory = nil
                }
            }
        }

        showCategoryEditorSheet = false
    }

    private func monthRangeText(for month: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfMonth(for: month)
        guard
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)
        else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "dd.MM"
        return "\(formatter.string(from: start)) — \(formatter.string(from: end))"
    }

    private func formattedMonthlyTotal(_ value: Double) -> String {
        let amount = formattedAmount(value)
        let code = viewModel.state.displayCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return amount }
        let symbol = MonetaCurrency(rawValue: code)?.symbol ?? code
        return "\(amount) \(symbol)"
    }

    private func updateCategoryGridWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        let rounded = width.rounded(.toNearestOrAwayFromZero)
        guard abs(rounded - categoryGridWidth) >= 1 else { return }
        categoryGridWidth = rounded
    }

    private func budgetStatusColor(_ status: BudgetStatus) -> Color {
        budgetStatusTintToken(status).color
    }

    private func categoryBudgetBadgeText(_ status: BudgetStatus) -> String? {
        CashflowBudgetLocalization.categoryBadgeText(for: status)
    }

    private func monthlyBudgetStatusText(_ snapshot: BudgetProgressSnapshot) -> String {
        let currency = cashflowCurrencyCodeLabel(viewModel.state.displayCurrency)
        return CashflowBudgetLocalization.monthlyStatus(
            for: kind,
            remaining: snapshot.remaining,
            currency: currency
        )
    }

    private func monthlyBudgetUsageText(_ snapshot: BudgetProgressSnapshot) -> String {
        let usedPercent = Int((min(max(snapshot.progress, 0), 1) * 100).rounded())
        return CashflowBudgetLocalization.monthlyUsage(for: kind, percent: usedPercent)
    }

    private func categoryStrokeStyle(for option: CashflowCategoryOption) -> AnyShapeStyle {
        if let summary = categoryBudgetSummary(for: option) {
            return AnyShapeStyle(budgetStatusColor(summary.status).opacity(0.8))
        }
        return AnyShapeStyle(kind.strokeGradient.opacity(0.62))
    }

    private func handleBudgetThresholdHaptics(
        previousSnapshot: BudgetProgressSnapshot?,
        newSnapshot: BudgetProgressSnapshot?,
        previousCategorySteps: [String: Int]
    ) {
        handleMonthlyBudgetHaptic(previousSnapshot: previousSnapshot, newSnapshot: newSnapshot)
        handleCategoryBudgetHaptics(newSnapshot: newSnapshot, previousSteps: previousCategorySteps)
    }

    private func handleMonthlyBudgetHaptic(
        previousSnapshot: BudgetProgressSnapshot?,
        newSnapshot: BudgetProgressSnapshot?
    ) {
        guard kind == .expense else { return }
        guard let newSnapshot else {
            lastBudgetHapticStep = -1
            return
        }

        let previousStep = previousSnapshot.map { BudgetThresholdHapticsPlan.step(for: $0.progress) } ?? -1
        let newStep = BudgetThresholdHapticsPlan.step(for: newSnapshot.progress)
        lastBudgetHapticStep = newStep
        guard newStep > previousStep else { return }

        if newStep >= 2 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else {
            UIImpactFeedbackGenerator(style: newStep == 1 ? .medium : .light).impactOccurred()
        }
    }

    private func handleCategoryBudgetHaptics(
        newSnapshot: BudgetProgressSnapshot?,
        previousSteps: [String: Int]
    ) {
        guard kind == .expense else { return }
        guard let newSnapshot else {
            lastCategoryBudgetSteps = [:]
            return
        }

        var updatedSteps: [String: Int] = [:]
        var strongestEscalation: Int = -1

        for item in newSnapshot.categorySnapshots {
            let newStep = BudgetThresholdHapticsPlan.step(for: item.progress)
            let previousStep = previousSteps[item.categoryRawValue] ?? -1
            updatedSteps[item.categoryRawValue] = newStep
            if newStep > previousStep {
                strongestEscalation = max(strongestEscalation, newStep)
            }
        }

        lastCategoryBudgetSteps = updatedSteps

        guard strongestEscalation >= 0 else { return }
        if strongestEscalation >= 2 {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

struct CashflowTransferTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel

    var body: some View {
        CashflowTransactionEditorView(
            viewModel: viewModel,
            transactionType: .transfer,
            showsTransactionTypeSection: false,
            customNavigationTitle: L("cashflow.operation.new_transfer")
        )
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
