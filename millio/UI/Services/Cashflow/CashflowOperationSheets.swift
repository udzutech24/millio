//
//  CashflowOperationSheets.swift
//  millio
//
//  Created by Codex on 01.03.2026.
//

import SwiftUI
import UIKit

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
    @State private var isLoadingMonthlyTotal: Bool = false
    @State private var monthTotalTask: Task<Void, Never>?
    @State private var showRecurringManagement: Bool = false
    @State private var showPlannedManagement: Bool = false
    @State private var showHelpSheet: Bool = false

    @State private var showCreateCategorySheet: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryIcon: String = CashflowCustomCategory.defaultIcon
    @State private var showCategoryEditorSheet: Bool = false
    @State private var showDeleteCategoryAlert: Bool = false
    @State private var categoryEditorMode: CashflowCategoryEditorMode = .create
    @State private var categoryEditorName: String = ""
    @State private var categoryEditorIcon: String = CashflowCustomCategory.defaultIcon
    @State private var pendingDeleteCategoryRaw: String?

    private let categoryColumns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let outerCornerRadius: CGFloat = 22
    private let innerCornerRadius: CGFloat = 16

    private var currentMonthStart: Date {
        Calendar.current.startOfMonth(for: Date())
    }

    private var canMoveForward: Bool {
        selectedMonth < currentMonthStart
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: selectedMonth).capitalized
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
            .navigationDestination(isPresented: $showRecurringManagement) {
                CashflowScheduledTransactionsView(
                    viewModel: viewModel,
                    kind: kind.categoryKind,
                    mode: .recurring
                )
            }
            .navigationDestination(isPresented: $showPlannedManagement) {
                CashflowScheduledTransactionsView(
                    viewModel: viewModel,
                    kind: kind.categoryKind,
                    mode: .plannedOneTime
                )
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
            .fullScreenCover(isPresented: $showCategoryEditorSheet) {
                CashflowCategoryEditorSheet(
                    mode: categoryEditorMode,
                    name: $categoryEditorName,
                    icon: $categoryEditorIcon
                ) { name, icon in
                    handleCategoryEditorSave(name: name, icon: icon)
                }
            }
            .alert("Удалить категорию?", isPresented: $showDeleteCategoryAlert) {
                Button("Отмена", role: .cancel) {
                    pendingDeleteCategoryRaw = nil
                }
                Button("Удалить", role: .destructive) {
                    guard let raw = pendingDeleteCategoryRaw else { return }
                    if viewModel.deleteCategory(rawValue: raw, kind: kind.categoryKind),
                       selectedCategory?.rawValue == raw {
                        selectedCategory = nil
                    }
                    pendingDeleteCategoryRaw = nil
                }
            } message: {
                Text("Связанные операции будут перенесены в безопасную системную категорию.")
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
            .accessibilityLabel("Подсказка по экрану \(kind.navigationTitle.lowercased())")
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
            Text(kind.monthlyTotalTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 2)

            HStack {
                Text("Итого")
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
        }
        .padding(12)
        .background(outerPanelBackground)
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            TextField("Поиск категории", text: $searchText)
                .textInputAutocapitalization(.words)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(innerPanelBackground)
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Управление операциями")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 2)

            HStack(spacing: 10) {
                managementButton(
                    title: "Регулярные",
                    icon: "repeat",
                    action: { showRecurringManagement = true }
                )

                managementButton(
                    title: "Запланированные",
                    icon: "calendar.badge.plus",
                    action: { showPlannedManagement = true }
                )
            }
        }
    }

    private func managementButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.92))
                            .overlay(
                                Circle()
                                    .stroke(kind.strokeGradient.opacity(0.7), lineWidth: 1)
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(innerPanelBackground)
        }
        .buttonStyle(.plain)
    }

    private var categoriesSection: some View {
        LazyVGrid(columns: categoryColumns, spacing: 10) {
            ForEach(categories) { option in
                Button {
                    selectedCategory = option
                } label: {
                    VStack(spacing: 8) {
                        CashflowCategoryIconView(
                            icon: option.icon,
                            fontSize: 18,
                            fontWeight: .semibold,
                            tint: AnyShapeStyle(AppColors.textPrimary)
                        )
                        Text(option.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(minHeight: 30, alignment: .center)

                        Text(formattedCategoryTotal(for: option))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 112)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(kind.strokeGradient.opacity(0.62), lineWidth: 1.1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Редактировать") {
                        openCategoryEditor(for: option)
                    }
                    if viewModel.canDeleteCategory(rawValue: option.rawValue, kind: kind.categoryKind) {
                        Button("Удалить", role: .destructive) {
                            pendingDeleteCategoryRaw = option.rawValue
                            showDeleteCategoryAlert = true
                        }
                    }
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

            guard !Task.isCancelled else { return }
            await MainActor.run {
                monthlyTotal = total
                categoryTotals = totalsByCategory
                isLoadingMonthlyTotal = false
            }
        }
    }

    private func formattedCategoryTotal(for option: CashflowCategoryOption) -> String {
        let value = categoryTotals[option.rawValue] ?? 0
        return formattedAmount(value)
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
        formatter.locale = Locale(identifier: "ru_RU")
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
}

/// Тестируемый источник кратких подсказок для экранов "Новый доход/расход".
struct CashflowCategoryHelpContent {
    let title: String
    let lines: [String]

    static func make(for kind: CashflowCategoryTransactionSheetKind) -> CashflowCategoryHelpContent {
        let intro = switch kind {
        case .income:
            "Экран «Доход» показывает категории доходов за выбранный месяц."
        case .expense:
            "Экран «Расход» показывает категории расходов за выбранный месяц."
        }

        let totalHint = switch kind {
        case .income:
            "Сверху видно итог доходов за месяц в валюте отображения."
        case .expense:
            "Сверху видно итог расходов за месяц в валюте отображения."
        }

        return CashflowCategoryHelpContent(
            title: "Как это работает",
            lines: [
                intro,
                totalHint,
                "Нажмите на категорию, чтобы добавить операцию в выбранной категории.",
                "Нажмите «+», чтобы добавить свою категорию (название и иконка).",
                "Удерживайте категорию, чтобы открыть меню: редактировать или удалить.",
                "При удалении категории связанные операции автоматически переносятся в безопасную системную категорию."
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
                        ForEach(Array(content.lines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .padding(.top, 1)
                                Text(line)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
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
        case .income: return "Новый доход"
        case .expense: return "Новый расход"
        }
    }

    var monthlyTotalTitle: String {
        switch self {
        case .income: return "Итого доход за месяц"
        case .expense: return "Итого расход за месяц"
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
            customNavigationTitle: "Новый перевод"
        )
    }
}

private struct CashflowCategoryQuickCreateSheet: View {
    private enum IconPickerTab: String, CaseIterable, Identifiable {
        case emoji = "Эмодзи"
        case symbols = "Иконки"

        var id: String { rawValue }
    }

    @Binding var name: String
    @Binding var icon: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool
    @State private var selectedTab: IconPickerTab = .emoji
    @State private var iconSearchText: String = ""

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
                        FinancesSectionHeader(title: "Название")
                        FinancesGlassCard {
                            TextField("Введите название", text: $name)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(AppColors.textPrimary)
                                .focused($isNameFieldFocused)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }

                        FinancesSectionHeader(title: "Иконка")
                        FinancesGlassCard {
                            VStack(spacing: 12) {
                                Picker("Тип иконки", selection: $selectedTab) {
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
                                        TextField("Поиск иконки (например: car, cart, heart)", text: $iconSearchText)
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
            .navigationTitle("Новая категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        onSave(name, icon)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
