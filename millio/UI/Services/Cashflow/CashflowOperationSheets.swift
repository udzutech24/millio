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

struct CashflowCategoryDeletionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let preview: CashflowCategoryDeletionPreview
    let onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTargetRaw: String

    init(
        viewModel: CashflowViewModel,
        preview: CashflowCategoryDeletionPreview,
        onDelete: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.preview = preview
        self.onDelete = onDelete
        _selectedTargetRaw = State(initialValue: preview.suggestedTargetOption.rawValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    sourceCategoryRow
                } header: {
                    Text(
                        String(
                            localized: "cashflow.category.delete.review.header",
                            defaultValue: "Delete review",
                            comment: "Header for delete category review section"
                        )
                    )
                } footer: {
                    Text(impactSummaryText)
                }

                Section {
                    Picker(
                        String(
                            localized: "cashflow.category.delete.target.title",
                            defaultValue: "Move linked data to",
                            comment: "Picker title for category delete target"
                        ),
                        selection: $selectedTargetRaw
                    ) {
                        ForEach(preview.availableTargetOptions) { option in
                            HStack(spacing: 10) {
                                CashflowCategoryIconView(
                                    icon: option.icon,
                                    fontSize: 16,
                                    fontWeight: .semibold,
                                    tint: AnyShapeStyle(AppColors.textPrimary)
                                )
                                Text(option.displayName)
                            }
                            .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text(
                        String(
                            localized: "cashflow.category.delete.target.footer",
                            defaultValue: "Transactions, budget limits, pins, and merchant mappings will be remapped to the selected category.",
                            comment: "Footer explaining what is remapped during category deletion"
                        )
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(GradientBackground())
            .navigationTitle(
                destructiveActionTitle
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cashflow.common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        destructiveConfirmTitle,
                        role: .destructive
                    ) {
                        onDelete(selectedTargetRaw)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var sourceCategoryRow: some View {
        HStack(spacing: 12) {
            CashflowCategoryIconView(
                icon: preview.sourceOption.icon,
                fontSize: 20,
                fontWeight: .semibold,
                tint: AnyShapeStyle(AppColors.textPrimary)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.sourceOption.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(categoryTypeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()
        }
        .listRowBackground(Color.white.opacity(0.04))
    }

    private var categoryTypeText: String {
        if preview.sourceOption.isCustom {
            return String(
                localized: "cashflow.category.delete.kind.custom",
                defaultValue: "Custom category",
                comment: "Delete category subtitle for custom category"
            )
        }

        return String(
            localized: "cashflow.category.delete.kind.system",
            defaultValue: "System category will be hidden after migration",
            comment: "Delete category subtitle for system category"
        )
    }

    private var destructiveActionTitle: String {
        if preview.sourceOption.isCustom {
            return String(
                localized: "cashflow.category.actions.delete",
                defaultValue: "Delete",
                comment: "Delete category action title"
            )
        }

        return String(
            localized: "cashflow.category.actions.archive",
            defaultValue: "Archive",
            comment: "Archive system category action title"
        )
    }

    private var destructiveConfirmTitle: String {
        if preview.sourceOption.isCustom {
            return String(
                localized: "cashflow.category.delete.confirm",
                defaultValue: "Delete category",
                comment: "Confirm button title for category delete flow"
            )
        }

        return String(
            localized: "cashflow.category.archive.confirm",
            defaultValue: "Archive category",
            comment: "Confirm button title for system category archive flow"
        )
    }

    private var impactSummaryText: String {
        let transactionText = String.localizedStringWithFormat(
            String(
                localized: "cashflow.category.delete.transactions.summary",
                defaultValue: "%d linked transactions",
                comment: "Summary of linked transactions for category deletion"
            ),
            preview.linkedTransactionCount
        )
        let budgetText = String.localizedStringWithFormat(
            String(
                localized: "cashflow.category.delete.budgets.summary",
                defaultValue: "%d linked budget limits",
                comment: "Summary of linked budget limits for category deletion"
            ),
            preview.linkedBudgetLimitCount
        )
        let totalsText = preview.totalsByCurrency.isEmpty
            ? String(
                localized: "cashflow.category.delete.amounts.empty",
                defaultValue: "No transaction amounts linked to this category.",
                comment: "Delete category summary when there are no linked transaction amounts"
            )
            : preview.totalsByCurrency
                .map { "\($0.amount.formatted(.number.precision(.fractionLength(0...2)))) \($0.currency)" }
                .joined(separator: ", ")

        return [transactionText, budgetText, totalsText].joined(separator: " • ")
    }
}

struct CashflowCategoryUndoBanner: View {
    let action: CashflowCategoryMutationUndoAction
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 8)

            Button(String(localized: "Undo")) {
                onUndo()
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AppColors.brandPrimary)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var title: String {
        action.isArchive
            ? String(
                localized: "cashflow.category.undo.archive.title",
                defaultValue: "Category archived",
                comment: "Undo banner title after archiving a category"
            )
            : String(
                localized: "cashflow.category.undo.delete.title",
                defaultValue: "Category deleted",
                comment: "Undo banner title after deleting a category"
            )
    }

    private var subtitle: String {
        let targetName = action.targetOption.displayName
        if action.isArchive {
            return String(
                localized: "cashflow.category.undo.archive.subtitle",
                defaultValue: "Linked data moved to %@.",
                comment: "Undo banner subtitle after archiving a category"
            ).replacingOccurrences(of: "%@", with: targetName)
        }

        return String(
            localized: "cashflow.category.undo.delete.subtitle",
            defaultValue: "Deleted category data moved to %@.",
            comment: "Undo banner subtitle after deleting a category"
        ).replacingOccurrences(of: "%@", with: targetName)
    }
}

/// Единая политика сетки категорий для экранов создания дохода/расхода.
/// На узких экранах обе сетки переключаются на 3 колонки, чтобы размещение
/// категорий в доходах и расходах оставалось консистентным. Для расходов с
/// лимитами делаем это раньше, потому что карточки становятся плотнее.
struct CashflowCategoryGridLayout {
    struct CardMetrics {
        let topRowMinHeight: CGFloat
        let contentSpacing: CGFloat
        let titleMinHeight: CGFloat
        let cardMinHeight: CGFloat
        let verticalPadding: CGFloat
        let amountTopPadding: CGFloat
        let usesFlexibleSpacer: Bool
        let footerMinHeight: CGFloat
    }

    enum PinAffordanceStyle {
        case hidden
        case compactBadge
        case regularButton
    }

    enum PinPlacement {
        case hidden
        case inlineBadge
        case overlayButton
    }

    static let compactColumns = 3
    static let regularColumns = 4
    static let compactWidthThreshold: CGFloat = 330
    static let budgetCompactWidthThreshold: CGFloat = 430
    static let columnSpacing: CGFloat = 8
    static let unifiedCardMinHeight: CGFloat = 94
    static let unifiedTopRowMinHeight: CGFloat = 18
    static let unifiedFooterMinHeight: CGFloat = 18

    static func columnCount(
        for kind: CashflowCategoryTransactionSheetKind,
        containerWidth: CGFloat,
        showsBudgetDetails: Bool = false
    ) -> Int {
        if showsBudgetDetails, containerWidth < budgetCompactWidthThreshold {
            return compactColumns
        }
        if containerWidth < compactWidthThreshold {
            return compactColumns
        }
        return regularColumns
    }

    static func columns(
        for kind: CashflowCategoryTransactionSheetKind,
        containerWidth: CGFloat,
        showsBudgetDetails: Bool = false
    ) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: columnSpacing),
            count: columnCount(
                for: kind,
                containerWidth: containerWidth,
                showsBudgetDetails: showsBudgetDetails
            )
        )
    }

    static func cardMetrics(showsBudgetDetails: Bool) -> CardMetrics {
        if showsBudgetDetails {
            return CardMetrics(
                topRowMinHeight: unifiedTopRowMinHeight,
                contentSpacing: 4,
                titleMinHeight: 22,
                cardMinHeight: unifiedCardMinHeight,
                verticalPadding: 7,
                amountTopPadding: 0,
                usesFlexibleSpacer: true,
                footerMinHeight: unifiedFooterMinHeight
            )
        }

        return CardMetrics(
            topRowMinHeight: unifiedTopRowMinHeight,
            contentSpacing: 4,
            titleMinHeight: 20,
            cardMinHeight: unifiedCardMinHeight,
            verticalPadding: 6,
            amountTopPadding: 4,
            usesFlexibleSpacer: true,
            footerMinHeight: unifiedFooterMinHeight
        )
    }

    /// Для обеих сеток не засоряем карточки пустыми пинами:
    /// unpinned скрыты, pinned получают компактный badge.
    static func pinAffordanceStyle(
        for kind: CashflowCategoryTransactionSheetKind,
        isPinned: Bool
    ) -> PinAffordanceStyle {
        switch kind {
        case .expense:
            return isPinned ? .compactBadge : .hidden
        case .income:
            return isPinned ? .compactBadge : .hidden
        }
    }

    static func pinPlacement(for style: PinAffordanceStyle) -> PinPlacement {
        switch style {
        case .hidden:
            return .hidden
        case .compactBadge:
            return .inlineBadge
        case .regularButton:
            return .overlayButton
        }
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

private struct CashflowCategoryTransactionSheet: View {
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
        formatter.locale = .autoupdatingCurrent
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
        switch kind {
        case .expense:
            return budgetSnapshot == nil
                ? budgetLocalized(ru: "Добавить лимиты", en: "Add limits")
                : budgetLocalized(ru: "Лимиты", en: "Limits")
        case .income:
            return budgetSnapshot == nil
                ? budgetLocalized(ru: "План", en: "Plan")
                : budgetLocalized(ru: "План", en: "Plan")
        }
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
                            ? String(localized: "cashflow.category.actions.unpin")
                            : String(localized: "cashflow.category.actions.pin"),
                        primaryActionIcon: viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)
                            ? "pin.slash"
                            : "pin",
                        onPrimaryAction: {
                            togglePinned(for: option)
                            closeCategoryActions()
                        },
                        secondaryActionTitle: String(
                            localized: "cashflow.category.actions.operations",
                            defaultValue: "Операции",
                            comment: "Category action button that opens filtered operations history"
                        ),
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
            circleToolbarButton(systemName: "xmark", accessibilityLabel: String(localized: "cashflow.common.close")) {
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

                VStack(spacing: 2) {
                    Text(monthTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                        .contentTransition(.numericText())

                    Text(monthRangeText(for: selectedMonth))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.86))
                        .monospacedDigit()
                }
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
                    accessibilityLabel: String(localized: "cashflow.operation.history_accessibility")
                ) {
                    showTransactionsHistory = true
                }

                circleToolbarButton(
                    systemName: "gearshape",
                    accessibilityLabel: String(localized: "Settings")
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
        let usesBudgetLayout = budgetSnapshot != nil

        VStack(alignment: usesBudgetLayout ? .leading : .center, spacing: 14) {
            if isLoadingMonthlyTotal {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(AppColors.textPrimary)
                        .scaleEffect(0.9)
                    Spacer()
                }
                .padding(.vertical, 18)
            } else {
                Text(formattedMonthlyTotal(monthlyTotal))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: usesBudgetLayout ? .leading : .center)
            }

            monthlyBudgetInlineSection
        }
        .frame(maxWidth: .infinity, alignment: usesBudgetLayout ? .leading : .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(innerPanelBackground)
    }

    @ViewBuilder
    private var monthlyBudgetInlineSection: some View {
        if let snapshot = budgetSnapshot {
            let style = budgetMonthlySummaryStyle(kind: kind, snapshot: snapshot)
            VStack(alignment: .leading, spacing: 10) {
                Text(monthlyBudgetUsageText(snapshot))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.usageText.color)

                GeometryReader { proxy in
                    let progress = min(max(snapshot.progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        Capsule(style: .continuous)
                            .fill(style.progressFill.color)
                            .frame(width: max(12, proxy.size.width * progress))
                    }
                }
                .frame(height: 8)

                Text(monthlyBudgetStatusText(snapshot))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.statusText.color)

                if snapshot.categoriesLimitOverflow > 0.0000001 {
                    Text(
                        budgetLocalized(
                            ru: kind == .expense
                                ? "Сумма лимитов категорий больше общего на \(formattedAmount(snapshot.categoriesLimitOverflow))"
                                : "Сумма планов категорий больше общего на \(formattedAmount(snapshot.categoriesLimitOverflow))",
                            en: "Category limits exceed total by \(formattedAmount(snapshot.categoriesLimitOverflow))"
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.92))
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
            ? String(localized: "cashflow.common.close", defaultValue: "Close")
            : String(localized: "cashflow.operation.search_category", defaultValue: "Search category")
        )
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            TextField(String(localized: "cashflow.operation.search_category"), text: $searchText)
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
                    .accessibilityLabel(String(localized: "cashflow.common.close"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var categoriesSection: some View {
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
                selectedCategory = option
            } label: {
                VStack(alignment: .leading, spacing: metrics.contentSpacing) {
                    HStack(alignment: .top) {
                        CashflowCategoryIconView(
                            icon: option.icon,
                            fontSize: 18,
                            fontWeight: .semibold,
                            tint: AnyShapeStyle(AppColors.textPrimary)
                        )
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, minHeight: metrics.titleMinHeight, alignment: .topLeading)

                    if metrics.usesFlexibleSpacer {
                        Spacer(minLength: 0)
                    }

                    Text(formattedCategoryTotal(for: option))
                        .font(.system(size: 18, weight: .bold))
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
                                        .font(.system(size: 10, weight: .medium))
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
                                .frame(height: 5)
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
                .accessibilityLabel(isPinned ? "Unpin category" : "Pin category")
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
            .accessibilityLabel("Pinned category")
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
        let calendar = Calendar.current
        let start = calendar.startOfMonth(for: selectedMonth)
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? selectedMonth
        let today = calendar.startOfDay(for: Date())
        let end = min(calendar.startOfDay(for: monthEnd), today)
        return (start: start, end: max(start, end))
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
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: value)) ?? "0"
        return amount
    }

    private func categoryBudgetLimitLabel(_ value: Double) -> String {
        switch kind {
        case .expense:
            return "Лимит \(formattedAmount(value))"
        case .income:
            return "План \(formattedAmount(value))"
        }
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
            ? String(localized: "cashflow.category.actions.delete")
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
        switch status {
        case .warning, .critical:
            return budgetLocalized(ru: "ПОЧТИ", en: "NEAR")
        case .exceeded:
            return budgetLocalized(ru: "СВЕРХ", en: "OVER")
        case .normal:
            return nil
        }
    }

    private func monthlyBudgetStatusText(_ snapshot: BudgetProgressSnapshot) -> String {
        let currency = cashflowCurrencyCodeLabel(viewModel.state.displayCurrency)
        switch kind {
        case .expense:
            if snapshot.remaining >= 0 {
                return budgetLocalized(
                    ru: "Осталось \(formattedAmount(snapshot.remaining)) \(currency)",
                    en: "\(formattedAmount(snapshot.remaining)) \(currency) remaining"
                )
            }
            return budgetLocalized(
                ru: "Перерасход \(formattedAmount(abs(snapshot.remaining))) \(currency)",
                en: "Over by \(formattedAmount(abs(snapshot.remaining))) \(currency)"
            )
        case .income:
            if snapshot.remaining <= 0.0000001 {
                return budgetLocalized(
                    ru: "План доходов выполнен",
                    en: "Income plan reached"
                )
            }
            return budgetLocalized(
                ru: "По плану осталось \(formattedAmount(snapshot.remaining)) \(currency)",
                en: "\(formattedAmount(snapshot.remaining)) \(currency) left in plan"
            )
        }
    }

    private func monthlyBudgetUsageText(_ snapshot: BudgetProgressSnapshot) -> String {
        let usedPercent = Int((min(max(snapshot.progress, 0), 1) * 100).rounded())
        return budgetLocalized(
            ru: kind == .expense
                ? "\(usedPercent)% от месячного лимита"
                : "\(usedPercent)% от плана доходов",
            en: kind == .expense
                ? "\(usedPercent)% of monthly limit"
                : "\(usedPercent)% of income plan"
        )
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

struct CashflowManagementEntry: Identifiable, Equatable {
    let title: String
    let icon: String
    let destination: CashflowManagementDestination
    let lineLimit: Int

    var id: CashflowManagementDestination { destination }

    static func entries(for categoryKind: CashflowCategoryKind) -> [CashflowManagementEntry] {
        if categoryKind == .expense {
            return [
                CashflowManagementEntry(
                    title: String(
                        localized: "cashflow.bulk_expense.entry.title",
                        defaultValue: "Mass import",
                        comment: "Compact entry title for bulk expense import"
                    ),
                    icon: "square.stack.3d.down.right.fill",
                    destination: .bulkImport,
                    lineLimit: 2
                ),
                CashflowManagementEntry(
                    title: String(
                        localized: "cashflow.management.planner_expenses.title",
                        defaultValue: "Planned",
                        comment: "Management entry title for planned expenses"
                    ),
                    icon: "calendar.badge.plus",
                    destination: .planned,
                    lineLimit: 2
                )
            ]
        }

        return [
            CashflowManagementEntry(
                title: String(
                    localized: "cashflow.management.recurring.title",
                    defaultValue: "Recurring",
                    comment: "Management entry title for recurring cashflow items"
                ),
                icon: "repeat",
                destination: .recurring,
                lineLimit: 1
            ),
            CashflowManagementEntry(
                title: String(
                    localized: "cashflow.management.income_plan.title",
                    defaultValue: "Income plan",
                    comment: "Management entry title for planned income items"
                ),
                icon: "calendar.badge.plus",
                destination: .planned,
                lineLimit: 2
            )
        ]
    }
}

enum CashflowManagementDestination: Hashable {
    case bulkImport
    case recurring
    case planned
}

/// Тестируемый источник кратких подсказок для экранов "Новый доход/расход".
struct CashflowCategoryHelpContent {
    let title: String
    let notes: [String]

    static func make(for kind: CashflowCategoryTransactionSheetKind) -> CashflowCategoryHelpContent {
        return CashflowCategoryHelpContent(
            title: String(localized: "cashflow.operation.help.title"),
            notes: [
                String(localized: "cashflow.operation.help.note.currency_first"),
                String(localized: "cashflow.operation.help.note.category_month")
            ]
        )
    }
}

private struct CashflowCategoryHelpSheet: View {
    let kind: CashflowCategoryTransactionSheetKind
    @Environment(\.dismiss) private var dismiss

    private var content: CashflowCategoryHelpContent {
        CashflowCategoryHelpContent.make(for: kind)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(content.notes.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.brandPrimary)
                                    .padding(.top, 1)
                                Text(line)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cashflow.common.close")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CashflowCategorySettingsSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryTransactionSheetKind

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var showActionsDialog: Bool = false
    @State private var showEditorSheet: Bool = false
    @State private var editorMode: CashflowCategoryEditorMode = .create
    @State private var editorName: String = ""
    @State private var editorIcon: String = CashflowCustomCategory.defaultIcon
    @State private var pendingDeletePreview: CashflowCategoryDeletionPreview?
    @State private var pendingUndoAction: CashflowCategoryMutationUndoAction?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var pendingActionCategory: CashflowCategoryOption?

    private var systemOptions: [CashflowCategoryOption] {
        viewModel.categoryOptions(
            for: kind.categoryKind,
            matching: searchText,
            includeHiddenSystem: true
        ).filter { !$0.isCustom }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                String(
                                    localized: "cashflow.category.settings.title",
                                    defaultValue: "Category settings",
                                    comment: "Category settings section title"
                                )
                            )
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                TextField(
                                    String(
                                        localized: "cashflow.operation.search_category",
                                        defaultValue: "Search category",
                                        comment: "Category settings search placeholder"
                                    ),
                                    text: $searchText
                                )
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(AppColors.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )

                            VStack(spacing: 10) {
                                ForEach(systemOptions) { option in
                                    categoryVisibilityRow(for: option)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(
                String(
                    localized: "cashflow.category.settings.title",
                    defaultValue: "Category settings",
                    comment: "Settings sheet title"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    }
                    .accessibilityLabel(String(localized: "cashflow.common.close"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .overlay(alignment: .bottom) {
            if let option = pendingActionCategory {
                CashflowCategoryActionOverlay(
                    isPresented: showActionsDialog,
                    categoryName: option.displayName,
                    categoryIcon: option.icon,
                    accentColor: kind.accentColor,
                    primaryActionTitle: nil,
                    primaryActionIcon: nil,
                    onPrimaryAction: nil,
                    secondaryActionTitle: nil,
                    secondaryActionIcon: nil,
                    onSecondaryAction: nil,
                    onEdit: {
                        closeSettingsCategoryActions()
                        openEditSheet(for: option)
                    },
                    deleteActionTitle: option.isCustom
                        ? String(localized: "cashflow.category.actions.delete")
                        : String(
                            localized: "cashflow.category.actions.archive",
                            defaultValue: "Archive",
                            comment: "Archive system category action title"
                        ),
                    deleteActionIcon: option.isCustom ? "trash" : "archivebox",
                    onDelete: viewModel.canDeleteCategory(rawValue: option.rawValue, kind: kind.categoryKind) ? {
                        closeSettingsCategoryActions()
                        presentDeleteCategoryFlow(for: option)
                    } : nil,
                    onDismiss: closeSettingsCategoryActions
                )
            }
        }
        .sheet(item: $pendingDeletePreview) { preview in
            CashflowCategoryDeletionSheet(viewModel: viewModel, preview: preview) { targetRaw in
                guard let undoAction = viewModel.performCategoryRemoval(
                    rawValue: preview.rawValue,
                    kind: preview.kind,
                    targetRawValue: targetRaw
                ) else {
                    return
                }
                presentUndoAction(undoAction)
                pendingDeletePreview = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let pendingUndoAction {
                CashflowCategoryUndoBanner(action: pendingUndoAction) {
                    guard viewModel.undoCategoryMutation(pendingUndoAction) else { return }
                    dismissUndoAction()
                } onDismiss: {
                    dismissUndoAction()
                }
            }
        }
        .fullScreenCover(isPresented: $showEditorSheet) {
            CashflowCategoryEditorSheet(
                mode: editorMode,
                name: $editorName,
                icon: $editorIcon
            ) { name, icon in
                handleSave(name: name, icon: icon)
            }
        }
    }

    private func categoryVisibilityRow(for option: CashflowCategoryOption) -> some View {
        let isVisible = viewModel.categoryOptions(for: kind.categoryKind).contains { $0.rawValue == option.rawValue }
        let canHide = option.rawValue != fallbackRaw

        return HStack(spacing: 12) {
            CashflowCategoryIconView(
                icon: option.icon,
                fontSize: 18,
                fontWeight: .semibold,
                tint: AnyShapeStyle(AppColors.textPrimary)
            )
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(
                    visibilityText(isVisible: isVisible, canHide: canHide)
                )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button {
                openActions(for: option)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "cashflow.common.edit"))

            Toggle(
                "",
                isOn: Binding(
                    get: { isVisible },
                    set: { newValue in
                        _ = viewModel.setSystemCategoryHidden(
                            kind: kind.categoryKind,
                            categoryRaw: option.rawValue,
                            isHidden: !newValue
                        )
                    }
                )
            )
            .labelsHidden()
            .tint(AppColors.brandPrimary)
            .disabled(!canHide)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var fallbackRaw: String {
        kind.categoryKind == .income ? IncomeCategory.other.rawValue : ExpenseCategory.other.rawValue
    }

    private func openEditSheet(for option: CashflowCategoryOption) {
        editorMode = .edit(rawValue: option.rawValue)
        editorName = option.displayName
        editorIcon = option.icon
        showEditorSheet = true
    }

    private func openActions(for option: CashflowCategoryOption) {
        pendingActionCategory = option
        showActionsDialog = true
    }

    private func closeSettingsCategoryActions() {
        showActionsDialog = false
        pendingActionCategory = nil
    }

    private func presentDeleteCategoryFlow(for option: CashflowCategoryOption) {
        pendingDeletePreview = viewModel.categoryDeletionPreview(
            rawValue: option.rawValue,
            kind: kind.categoryKind
        )
    }

    private func presentUndoAction(_ action: CashflowCategoryMutationUndoAction) {
        undoDismissTask?.cancel()
        pendingUndoAction = action
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            pendingUndoAction = nil
        }
    }

    private func dismissUndoAction() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        pendingUndoAction = nil
    }

    private func visibilityText(isVisible: Bool, canHide: Bool) -> String {
        if !canHide {
            return String(localized: "cashflow.category.visibility.always")
        }
        if isVisible {
            return String(localized: "cashflow.category.visibility.visible")
        }
        return String(localized: "cashflow.category.visibility.hidden")
    }

    private func handleSave(name: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch editorMode {
        case .create:
            break
        case .edit(let rawValue):
            guard viewModel.renameCategory(
                rawValue: rawValue,
                kind: kind.categoryKind,
                newName: trimmed,
                newIcon: icon
            ) else { return }
        }

        showEditorSheet = false
    }
}

enum CashflowCategoryTransactionSheetKind {
    case income
    case expense

    var transactionType: CashflowTransactionType {
        switch self {
        case .income: return .income
        case .expense: return .expense
        }
    }

    var categoryKind: CashflowCategoryKind {
        switch self {
        case .income: return .income
        case .expense: return .expense
        }
    }

    var navigationTitle: String {
        switch self {
        case .income: return String(localized: "cashflow.operation.new_income")
        case .expense: return String(localized: "cashflow.operation.new_expense")
        }
    }

    var monthlyTotalTitle: String {
        switch self {
        case .income: return String(localized: "cashflow.operation.total_income_for_month")
        case .expense: return String(localized: "cashflow.operation.total_expense_for_month")
        }
    }

    /// Фильтр истории, соответствующий текущему типу листа.
    var historyFilter: CashflowHistoryTypeFilter {
        switch self {
        case .income: return .income
        case .expense: return .expense
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .income: return AppColors.incomeGradient
        case .expense: return AppColors.expenseGradient
        }
    }

    var accentColor: Color {
        gradientColors.first ?? AppColors.brandPrimary
    }

    var strokeGradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    func amountColor(for value: Double) -> Color {
        switch cashflowValueTone(for: value) {
        case .neutral:
            return Color.white.opacity(0.78)
        case .positive:
            return self == .income ? Color(hex: "6DFFC7") : Color(hex: "FF6666")
        case .negative:
            return self == .income ? Color(hex: "FF6666") : Color(hex: "6DFFC7")
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
            customNavigationTitle: String(localized: "cashflow.operation.new_transfer")
        )
    }
}

private struct CashflowCategoryQuickCreateSheet: View {
    private enum IconPickerTab: String, CaseIterable, Identifiable {
        case emoji = "Emoji"
        case symbols = "Icons"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .emoji:
                return String(localized: "Эмодзи")
            case .symbols:
                return String(localized: "Иконки")
            }
        }
    }

    @Binding var name: String
    @Binding var icon: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool
    @State private var selectedTab: IconPickerTab = .emoji
    @State private var iconSearchText: String = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredSymbolIcons: [String] {
        let query = iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return CashflowCustomCategory.allowedSFSymbolIcons }
        return CashflowCustomCategory.allowedSFSymbolIcons.filter { $0.lowercased().contains(query) }
    }

    private var visibleIcons: [String] {
        switch selectedTab {
        case .emoji:
            return CashflowCustomCategory.allowedEmojiIcons
        case .symbols:
            return filteredSymbolIcons
        }
    }

    private var suggestedIcons: [String] {
        CashflowCategoryIconSuggestionEngine.suggestedIcons(forExpenseName: name)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        FinancesSectionHeader(title: String(localized: "cashflow.editor.category_name"))
                        FinancesGlassCard {
                            TextField("cashflow.editor.enter_name", text: $name)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(AppColors.textPrimary)
                                .focused($isNameFieldFocused)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }

                        FinancesSectionHeader(title: String(localized: "cashflow.editor.category_icon"))
                        FinancesGlassCard {
                            VStack(spacing: 12) {
                                if !suggestedIcons.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(
                                            String(
                                                localized: "cashflow.editor.icon_suggestions",
                                                defaultValue: "Suggested icons",
                                                comment: "Suggested icons title for category creation"
                                            )
                                        )
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppColors.textSecondary)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 10) {
                                                ForEach(suggestedIcons, id: \.self) { suggested in
                                                    Button {
                                                        icon = suggested
                                                    } label: {
                                                        CashflowCategoryIconView(
                                                            icon: suggested,
                                                            fontSize: 22,
                                                            fontWeight: .semibold,
                                                            tint: AnyShapeStyle(icon == suggested ? AppColors.textPrimary : AppColors.textSecondary)
                                                        )
                                                        .frame(width: 52, height: 52)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                                .fill(icon == suggested ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                                        .stroke(Color.white.opacity(icon == suggested ? 0.24 : 0.10), lineWidth: 1)
                                                                )
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.horizontal, 2)
                                        }
                                    }
                                }

                                Picker(String(localized: "cashflow.editor.icon_type"), selection: $selectedTab) {
                                    ForEach(IconPickerTab.allCases) { tab in
                                        Text(tab.localizedTitle).tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)

                                if selectedTab == .symbols {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AppColors.textTertiary)
                                        TextField("cashflow.editor.icon_search_hint", text: $iconSearchText)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(AppColors.textPrimary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                    )
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                                    ForEach(visibleIcons, id: \.self) { symbol in
                                    Button {
                                        icon = symbol
                                    } label: {
                                        CashflowCategoryIconView(
                                            icon: symbol,
                                            fontSize: 22,
                                            fontWeight: .semibold,
                                            tint: AnyShapeStyle(icon == symbol ? AppColors.textPrimary : AppColors.textSecondary)
                                        )
                                            .frame(width: 54, height: 54)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(icon == symbol ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                            .stroke(Color.white.opacity(icon == symbol ? 0.24 : 0.10), lineWidth: 1)
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            }
                            .padding(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
            }
            .navigationTitle("cashflow.editor.new_category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    }
                    .accessibilityLabel(String(localized: "cashflow.common.cancel"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(name, icon)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(canSave ? Color(hex: "6DFFC7") : AppColors.textSecondary.opacity(0.55))
                    }
                    .accessibilityLabel(String(localized: "cashflow.common.save"))
                    .disabled(!canSave)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    isNameFieldFocused = true
                }
                selectedTab = CashflowCustomCategory.isSFSymbolIcon(icon) ? .symbols : .emoji
                iconSearchText = ""
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
