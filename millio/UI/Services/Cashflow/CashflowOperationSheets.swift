//
//  CashflowOperationSheets.swift
//  millio
//
//  Created by Codex on 01.03.2026.
//

import SwiftUI
import UIKit

/// Единая политика сетки категорий для экранов создания дохода/расхода.
/// Для расходов на узких экранах уменьшаем количество колонок до 3,
/// чтобы подписи категорий оставались читаемыми в одну строку.
struct CashflowCategoryGridLayout {
    static let compactExpenseColumns = 3
    static let regularColumns = 4
    static let compactWidthThreshold: CGFloat = 330
    static let columnSpacing: CGFloat = 8

    static func columnCount(
        for kind: CashflowCategoryTransactionSheetKind,
        containerWidth: CGFloat
    ) -> Int {
        if kind == .expense, containerWidth < compactWidthThreshold {
            return compactExpenseColumns
        }
        return regularColumns
    }

    static func columns(
        for kind: CashflowCategoryTransactionSheetKind,
        containerWidth: CGFloat
    ) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: columnSpacing),
            count: columnCount(for: kind, containerWidth: containerWidth)
        )
    }
}

struct CashflowIncomeTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel

    var body: some View {
        CashflowCategoryTransactionSheet(viewModel: viewModel, kind: .income)
    }
}

struct CashflowExpenseTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel

    var body: some View {
        CashflowCategoryTransactionSheet(viewModel: viewModel, kind: .expense)
    }
}

private struct CashflowCategoryTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryTransactionSheetKind

    @Environment(\.dismiss) private var dismiss

    @State private var selectedMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedCategory: CashflowCategoryOption?
    @State private var searchText: String = ""
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
    @State private var showHelpSheet: Bool = false
    @State private var showBulkExpenseImportSheet: Bool = false
    @State private var showBudgetSetupSheet: Bool = false

    @State private var showCreateCategorySheet: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryIcon: String = CashflowCustomCategory.defaultIcon
    @State private var showCategoryEditorSheet: Bool = false
    @State private var showDeleteCategoryAlert: Bool = false
    @State private var categoryEditorMode: CashflowCategoryEditorMode = .create
    @State private var categoryEditorName: String = ""
    @State private var categoryEditorIcon: String = CashflowCustomCategory.defaultIcon
    @State private var pendingDeleteCategoryRaw: String?
    @State private var categoryGridWidth: CGFloat = UIScreen.main.bounds.width

    private let outerCornerRadius: CGFloat = 22
    private let innerCornerRadius: CGFloat = 16

    private var categoryColumns: [GridItem] {
        CashflowCategoryGridLayout.columns(
            for: kind,
            containerWidth: categoryGridWidth
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
        formatter.setLocalizedDateFormatFromTemplate("LLLL y")
        return formatter.string(from: selectedMonth).localizedCapitalized
    }

    private var categories: [CashflowCategoryOption] {
        viewModel.categoryOptions(for: kind.categoryKind, matching: searchText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        headerSection
                        monthSelectorSection
                        monthlyTotalSection
                        managementSection
                        searchSection
                        categoriesSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 112)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()

                floatingAddCategoryButton
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
                    onSave: { dismiss() }
                )
            }
            .navigationDestination(isPresented: $showTransactionsHistory) {
                CashflowTransactionsHistoryView(
                    viewModel: viewModel,
                    showsDismissButton: false,
                    initialFilter: kind.historyFilter
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
            .sheet(isPresented: $showHelpSheet) {
                CashflowCategoryHelpSheet(kind: kind)
            }
            .sheet(isPresented: $showBulkExpenseImportSheet) {
                CashflowBulkExpenseImportSheet(
                    viewModel: viewModel,
                    month: selectedMonth,
                    onComplete: reloadMonthlyTotal
                )
            }
            .sheet(isPresented: $showBudgetSetupSheet) {
                BudgetSetupSheet(
                    periodTitle: monthTitle,
                    currencyCode: cashflowCurrencyCodeLabel(viewModel.state.displayCurrency),
                    existingAmount: budgetTotalLimit,
                    categoryOptions: viewModel.categoryOptions(for: .expense),
                    existingCategoryLimits: categoryBudgetLimits,
                    categorySnapshots: budgetSnapshot?.categorySnapshots ?? [],
                    onSave: { amount, limits in
                        viewModel.saveMonthlyBudgetConfiguration(
                            month: selectedMonth,
                            totalAmount: amount,
                            categoryLimits: limits,
                            currency: viewModel.state.displayCurrency
                        )
                        reloadMonthlyTotal()
                    },
                    onDelete: budgetTotalLimit == nil ? nil : {
                        viewModel.deleteMonthlyBudgetLimit(month: selectedMonth)
                        reloadMonthlyTotal()
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
            .alert(String(localized: "cashflow.operation.delete_category.title"), isPresented: $showDeleteCategoryAlert) {
                Button(String(localized: "cashflow.common.cancel"), role: .cancel) {
                    pendingDeleteCategoryRaw = nil
                }
                Button(String(localized: "cashflow.history.detail.delete"), role: .destructive) {
                    guard let raw = pendingDeleteCategoryRaw else { return }
                    if viewModel.deleteCategory(rawValue: raw, kind: kind.categoryKind),
                       selectedCategory?.rawValue == raw {
                        selectedCategory = nil
                    }
                    pendingDeleteCategoryRaw = nil
                }
            } message: {
                Text("cashflow.operation.delete_category.message")
            }
            .onAppear {
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
        .presentationDragIndicator(.visible)
    }

    private var headerSection: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    .frame(width: 44, height: 44)
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

            Spacer()

            Button {
                showTransactionsHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    .frame(width: 44, height: 44)
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
            .accessibilityLabel(String(localized: "cashflow.operation.history_accessibility"))

            Button {
                showHelpSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    .frame(width: 44, height: 44)
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
            .accessibilityLabel(
                String(
                    format: String(localized: "cashflow.category.hint_accessibility_format"),
                    kind.navigationTitle.lowercased()
                )
            )
        }
        .padding(.top, 6)
    }

    private var monthSelectorSection: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                        .frame(width: 32, height: 32)
                        .background(toolbarCircleBackground)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))

                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(canMoveForward ? AppColors.textPrimary.opacity(0.9) : AppColors.textSecondary.opacity(0.45))
                        .frame(width: 32, height: 32)
                        .background(toolbarCircleBackground)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            let period = monthRangeText(for: selectedMonth)
            Text(period)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(outerPanelBackground)
    }

    private var monthlyTotalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.monthlyTotalTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if kind == .expense {
                    Button {
                        showBudgetSetupSheet = true
                    } label: {
                        Text(budgetSnapshot == nil ? budgetLocalized(ru: "Добавить лимит", en: "Add limit") : budgetLocalized(ru: "Лимиты", en: "Limits"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(innerPanelBackground)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)

            HStack {
                Text("cashflow.operation.total")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                Spacer()
                if isLoadingMonthlyTotal {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                        .scaleEffect(0.9)
                } else {
                    Text(formattedMonthlyTotal(monthlyTotal))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(kind.amountColor(for: monthlyTotal))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(innerPanelBackground)

            if kind == .expense {
                monthlyBudgetInlineSection
            }
        }
        .padding(12)
        .background(outerPanelBackground)
    }

    @ViewBuilder
    private var monthlyBudgetInlineSection: some View {
        if let snapshot = budgetSnapshot {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(budgetLocalized(ru: "Лимит месяца", en: "Monthly limit"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    Spacer()
                    Text("\(formattedAmount(snapshot.spent)) / \(formattedAmount(snapshot.limit))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(budgetStatusColor(snapshot.status))
                }

                GeometryReader { proxy in
                    let progress = min(max(snapshot.progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        Capsule(style: .continuous)
                            .fill(budgetStatusColor(snapshot.status))
                            .frame(width: max(12, proxy.size.width * progress))
                    }
                }
                .frame(height: 8)

                Text(monthlyBudgetStatusText(snapshot))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(budgetStatusColor(snapshot.status))

                if snapshot.categoriesLimitOverflow > 0.0000001 {
                    Text(
                        budgetLocalized(
                            ru: "Сумма лимитов категорий больше общего на \(formattedAmount(snapshot.categoriesLimitOverflow))",
                            en: "Category limits exceed total by \(formattedAmount(snapshot.categoriesLimitOverflow))"
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.92))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(innerPanelBackground)
        } else {
            Button {
                showBudgetSetupSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(
                        budgetLocalized(
                            ru: "Добавить лимит на месяц и по категориям",
                            en: "Add monthly and category limits"
                        )
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(innerPanelBackground)
            }
            .buttonStyle(.plain)
        }
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            TextField(String(localized: "cashflow.operation.search_category"), text: $searchText)
                .textInputAutocapitalization(.words)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(innerPanelBackground)
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cashflow.operation.management")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 2)

            let entries = CashflowManagementEntry.entries(for: kind.categoryKind)
            HStack(spacing: 10) {
                ForEach(entries) { entry in
                    managementButton(entry: entry)
                }
            }
        }
    }

    private func managementButton(entry: CashflowManagementEntry) -> some View {
        Button {
            handleManagementTap(entry)
        } label: {
            let iconView = Image(systemName: entry.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.92))
                        .overlay(
                            Circle()
                                .stroke(kind.strokeGradient.opacity(0.7), lineWidth: 1)
                        )
                )

            HStack(spacing: 10) {
                iconView

                Spacer(minLength: 0)

                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(entry.lineLimit)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)

                // Symmetric placeholder to keep the title visually centered.
                iconView
                    .opacity(0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            .background(innerPanelBackground)
        }
        .buttonStyle(.plain)
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
                Button {
                    selectedCategory = option
                } label: {
                    let summary = categoryBudgetSummary(for: option)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            CashflowCategoryIconView(
                                icon: option.icon,
                                fontSize: 18,
                                fontWeight: .semibold,
                                tint: AnyShapeStyle(AppColors.textPrimary)
                            )
                            Spacer(minLength: 6)
                            if let summary, let badge = categoryBudgetBadgeText(summary.status) {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(budgetStatusColor(summary.status))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(budgetStatusColor(summary.status).opacity(0.14))
                                    )
                            }
                        }

                        Text(option.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)

                        Spacer(minLength: 0)

                        Text(formattedCategoryTotal(for: option))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(summary == nil ? AppColors.textSecondary : AppColors.textPrimary.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if let summary {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(formattedAmount(summary.spent))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(budgetStatusColor(summary.status))
                                        .lineLimit(1)
                                    Text("/")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.42))
                                    Text(formattedAmount(summary.limit))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(0.68))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
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
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(categoryStrokeStyle(for: option), lineWidth: 1.1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Edit") {
                        openCategoryEditor(for: option)
                    }
                    if viewModel.canDeleteCategory(rawValue: option.rawValue, kind: kind.categoryKind) {
                        Button("Delete", role: .destructive) {
                            pendingDeleteCategoryRaw = option.rawValue
                            showDeleteCategoryAlert = true
                        }
                    }
                }
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
                        .frame(width: 64, height: 64)
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

    private func reloadMonthlyTotal() {
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
            let budgetSummary: (plan: BudgetPlan?, snapshot: BudgetProgressSnapshot?, categoryLimits: [String: Double]) =
                kind == .expense
                ? await viewModel.expenseBudgetSummary(for: selectedMonth, in: viewModel.state.displayCurrency)
                : (nil, nil, [:])

            guard !Task.isCancelled else { return }
            await MainActor.run {
                let previousBudgetSnapshot = budgetSnapshot
                let previousCategorySteps = lastCategoryBudgetSteps
                monthlyTotal = total
                categoryTotals = totalsByCategory
                budgetSnapshot = budgetSummary.snapshot
                categoryBudgetLimits = budgetSummary.categoryLimits
                budgetTotalLimit = budgetSummary.plan?.totalLimitAmount
                isLoadingMonthlyTotal = false
                handleBudgetThresholdHaptics(
                    previousSnapshot: previousBudgetSnapshot,
                    newSnapshot: budgetSummary.snapshot,
                    previousCategorySteps: previousCategorySteps
                )
            }
        }
    }

    private func formattedCategoryTotal(for option: CashflowCategoryOption) -> String {
        let value = categoryTotals[option.rawValue] ?? 0
        return formattedAmount(value)
    }

    private func categoryBudgetSummary(for option: CashflowCategoryOption) -> BudgetCategoryProgressSnapshot? {
        guard kind == .expense else { return nil }
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

    private func openCategoryEditor(for option: CashflowCategoryOption) {
        categoryEditorMode = .edit(rawValue: option.rawValue)
        categoryEditorName = option.displayName
        categoryEditorIcon = option.icon
        showCategoryEditorSheet = true
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
                if let resolved = viewModel.categoryOptions(for: kind.categoryKind).first(where: {
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
        formatter.dateFormat = "dd.MM.yyyy"
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
        switch status {
        case .normal:
            return Color(hex: "6DFFC7")
        case .warning:
            return Color(hex: "FFD66D")
        case .critical:
            return Color(hex: "FF9B6A")
        case .exceeded:
            return Color(hex: "FF6666")
        }
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
        if snapshot.remaining >= 0 {
            return budgetLocalized(
                ru: "Осталось \(formattedAmount(snapshot.remaining)) \(cashflowCurrencyCodeLabel(viewModel.state.displayCurrency))",
                en: "\(formattedAmount(snapshot.remaining)) \(cashflowCurrencyCodeLabel(viewModel.state.displayCurrency)) remaining"
            )
        }
        return budgetLocalized(
            ru: "Перерасход \(formattedAmount(abs(snapshot.remaining))) \(cashflowCurrencyCodeLabel(viewModel.state.displayCurrency))",
            en: "Over by \(formattedAmount(abs(snapshot.remaining))) \(cashflowCurrencyCodeLabel(viewModel.state.displayCurrency))"
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
                Color.black.ignoresSafeArea()
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
            customNavigationTitle: "New transfer"
        )
    }
}

private struct CashflowCategoryQuickCreateSheet: View {
    private enum IconPickerTab: String, CaseIterable, Identifiable {
        case emoji = "Emoji"
        case symbols = "Icons"

        var id: String { rawValue }
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
                                Picker(String(localized: "cashflow.editor.icon_type"), selection: $selectedTab) {
                                    ForEach(IconPickerTab.allCases) { tab in
                                        Text(tab.rawValue).tag(tab)
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
