//
//  CashflowUnifiedEntryView.swift
//  millio
//
//  Единый экран быстрого ввода дохода/расхода (Фаза 3 редизайна add-flow).
//  Перенесён verbatim из CashflowOperationSheets.swift (чекпоинт 3a).
//  Тип пока сохраняет имя CashflowCategoryTransactionSheet — переименование отложено.
//

import SwiftUI
import UIKit

struct CashflowCategoryTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryTransactionSheetKind
    let initialHistoryCardID: String?

    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State var selectedMonth: Date
    @State var selectedCategory: CashflowCategoryOption?
    @State var searchText: String = ""
    @State var isSearchExpanded: Bool = false
    // Фаза 2 редизайна add-flow (§2.2): cap избранных категорий в сетке по умолчанию.
    @State var showAllCategories: Bool = false
    @AppStorage("cashflow_category_cap_coachmark_seen") var hasSeenCategoryCapCoachMark: Bool = false
    @State var showCategoryCapCoachMark: Bool = false
    @State var monthlyTotal: Double = 0
    @State var categoryTotals: [String: Double] = [:]
    @State var budgetSnapshot: BudgetProgressSnapshot?
    @State var categoryBudgetLimits: [String: Double] = [:]
    @State var budgetTotalLimit: Double?
    @State var lastBudgetHapticStep: Int = -1
    @State var lastCategoryBudgetSteps: [String: Int] = [:]
    @State var isLoadingMonthlyTotal: Bool = false
    @State var monthTotalTask: Task<Void, Never>?
    @State var showRecurringManagement: Bool = false
    @State var showPlannedManagement: Bool = false
    @State var showTransactionsHistory: Bool = false
    @State var showSettingsSheet: Bool = false
    @State var showBulkExpenseImportSheet: Bool = false
    @State var showBudgetSetupSheet: Bool = false
    @State var showMoreSheet: Bool = false
    /// Действие из листа «…» выполняется в его onDismiss: iOS не открывает новый sheet,
    /// пока предыдущий ещё закрывается.
    @State var pendingMoreAction: CashflowEntryMoreAction?

    @State var showCreateCategorySheet: Bool = false
    @State var newCategoryName: String = ""
    @State var newCategoryIcon: String = CashflowCustomCategory.defaultIcon
    @State var showCategoryEditorSheet: Bool = false
    @State var showCategoryActionsDialog: Bool = false
    @State var categoryEditorMode: CashflowCategoryEditorMode = .create
    @State var categoryEditorName: String = ""
    @State var categoryEditorIcon: String = CashflowCustomCategory.defaultIcon
    @State var pendingCategoryDeletionPreview: CashflowCategoryDeletionPreview?
    @State var pendingCategoryUndoAction: CashflowCategoryMutationUndoAction?
    @State var categoryUndoDismissTask: Task<Void, Never>?
    @State var pendingActionCategory: CashflowCategoryOption?
    @State var categoryGridWidth: CGFloat = UIScreen.main.bounds.width
    @State var highlightedCategoryRaw: String?
    @State var categoryUpdateFeedbackPlan: CashflowCategoryUpdateFeedbackPlan?
    @State var categoryFeedbackSequence: Int = 0
    @State var hasCompletedInitialLoad: Bool = false
    @State var suppressNextCategoryTap: Bool = false
    @State var showReorderSheet: Bool = false
    @State var sortMode: CashflowCategorySortMode
    @State var frozenCategoryOrder: [String] = []
    @State var snapshotRevision: Int = 0
    @State var snapshotCache = CashflowUnifiedEntrySnapshotCache()
    @FocusState var isSearchFieldFocused: Bool
    let outerCornerRadius: CGFloat = 22
    let innerCornerRadius: CGFloat = 16

    init(
        viewModel: CashflowViewModel,
        kind: CashflowCategoryTransactionSheetKind,
        initialHistoryCardID: String?,
        initialMonth: Date? = nil
    ) {
        self.viewModel = viewModel
        self.kind = kind
        self.initialHistoryCardID = initialHistoryCardID
        _selectedMonth = State(
            initialValue: CashflowMonthSelectionPolicy.canonicalMonth(initialMonth ?? .now)
        )
        _sortMode = State(initialValue: CashflowCategorySortPreferences.load(for: kind.categoryKind))
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
                            searchFieldSection
                            categoriesSectionHeader
                            categoryCapCoachMarkBanner
                            categoriesSection
                            historyShortcutSection
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
                }
            }
            .overlay(alignment: .bottom) { categoryActionsOverlay }
            .sheet(item: $pendingCategoryDeletionPreview) { preview in
                categoryDeletionSheet(for: preview)
            }
            .overlay(alignment: .bottom) { categoryUndoOverlay }
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
            .sheet(isPresented: $showMoreSheet, onDismiss: performPendingMoreAction) {
                CashflowEntryMoreSheet(
                    kind: kind,
                    planTitle: planButtonTitle,
                    sortMode: $sortMode,
                    onSelect: { pendingMoreAction = $0 }
                )
            }
            .sheet(isPresented: $showReorderSheet) {
                CashflowCategoryReorderSheet(viewModel: viewModel, kind: kind.categoryKind)
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
                    kind: kind.categoryKind,
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
                        reloadMonthlyTotal(forceRefresh: true)
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
                        reloadMonthlyTotal(forceRefresh: true)
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
            .onAppear {
                // prepare() переехал в CashflowUnifiedEntryContainer — он вызывается один раз на
                // открытие экрана. Здесь остаётся только пересчёт месячного среза: он зависит от
                // page-local состояния (kind + selectedMonth) и уже кэширован snapshotCache.
                reloadMonthlyTotal()
                if !hasSeenCategoryCapCoachMark {
                    showCategoryCapCoachMark = true
                    hasSeenCategoryCapCoachMark = true
                }
            }
            .onChange(of: selectedMonth) { _, _ in
                reloadMonthlyTotal()
            }
            .onChange(of: sortMode) { _, newValue in
                CashflowCategorySortPreferences.save(newValue, for: kind.categoryKind)
                freezeCategoryOrder()
            }
            .onDisappear {
                monthTotalTask?.cancel()
                monthTotalTask = nil
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    var searchFieldSection: some View {
        if shouldShowSearchField {
            searchSection
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    var searchSection: some View {
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

    var shouldShowSearchField: Bool {
        isSearchExpanded || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleSearch() {
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

    func performPendingMoreAction() {
        guard let action = pendingMoreAction else { return }
        pendingMoreAction = nil
        switch action {
        case .search:
            withAnimation(AppAnimation.standard) { isSearchExpanded = true }
            isSearchFieldFocused = true
        case .management(let destination):
            handleManagementTap(destination)
        case .monthPlan:
            showBudgetSetupSheet = true
        case .reorderCategories:
            showReorderSheet = true
        case .screenSettings:
            showSettingsSheet = true
        case .createCategory:
            showCreateCategorySheet = true
        }
    }

    func handleManagementTap(_ destination: CashflowManagementDestination) {
        switch destination {
        case .bulkImport:
            showBulkExpenseImportSheet = true
        case .recurring:
            showRecurringManagement = true
        case .planned:
            showPlannedManagement = true
        }
    }

    @ViewBuilder
    func scheduledManagementSheet(mode: CashflowScheduledTransactionsMode) -> some View {
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

    var historyShortcutSection: some View {
        CashflowUnifiedEntryHistorySection(
            viewModel: viewModel,
            kind: kind,
            month: selectedMonth,
            onOpenPaidHistory: {
                pendingActionCategory = nil
                showTransactionsHistory = true
            },
            onOpenUpcoming: {
                showPlannedManagement = true
            }
        )
    }

    var outerPanelBackground: some View {
        RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.24))
            .overlay(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .stroke(kind.strokeGradient.opacity(0.76), lineWidth: 1)
            )
    }

    var innerPanelBackground: some View {
        RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.30))
            .overlay(
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }

    func openOperations(for option: CashflowCategoryOption) {
        pendingActionCategory = option
        showCategoryActionsDialog = false
        showTransactionsHistory = true
    }

    func formattedAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: value)) ?? "0"
        return amount
    }

}

// internal, а не private: расширения экрана лежат в соседних файлах
// (…Header/…CategoryGrid/…DataLoading) и тоже считают начало месяца.
extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
