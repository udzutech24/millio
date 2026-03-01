//
//  CashflowOperationSheets.swift
//  millio
//
//  Created by Codex on 01.03.2026.
//

import SwiftUI

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
    @State private var isLoadingMonthlyTotal: Bool = false
    @State private var monthTotalTask: Task<Void, Never>?

    @State private var showCreateCategorySheet: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryIcon: String = CashflowCustomCategory.defaultIcon
    @State private var showCategoryEditorSheet: Bool = false
    @State private var showDeleteCategoryAlert: Bool = false
    @State private var categoryEditorMode: CashflowCategoryEditorMode = .create
    @State private var categoryEditorName: String = ""
    @State private var categoryEditorIcon: String = CashflowCustomCategory.defaultIcon
    @State private var pendingDeleteCategoryRaw: String?

    private let categoryColumns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

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
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        monthSelectorSection
                        monthlyTotalSection
                        searchSection
                        categoriesSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
            }
            .navigationTitle(kind.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
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
            .sheet(isPresented: $showCreateCategorySheet) {
                CashflowCategoryQuickCreateSheet(
                    name: $newCategoryName,
                    icon: $newCategoryIcon,
                    onSave: handleCreateCategory
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
            .alert("Удалить категорию?", isPresented: $showDeleteCategoryAlert) {
                Button("Отмена", role: .cancel) {
                    pendingDeleteCategoryRaw = nil
                }
                Button("Удалить", role: .destructive) {
                    guard let raw = pendingDeleteCategoryRaw else { return }
                    if viewModel.deleteCustomCategory(rawValue: raw, kind: kind.categoryKind),
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

    private var monthSelectorSection: some View {
        FinancesGlassCard(accentColor: kind.gradientColors.first) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canMoveForward ? AppColors.textPrimary : AppColors.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(canMoveForward ? 0.08 : 0.04)))
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
        }
    }

    private var monthlyTotalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FinancesSectionHeader(title: kind.monthlyTotalTitle)
            FinancesGlassCard(accentColor: kind.gradientColors.first) {
                HStack {
                    Text("Итого")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    if isLoadingMonthlyTotal {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .scaleEffect(0.9)
                    } else {
                        Text(formattedMonthlyTotal(monthlyTotal))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: kind.gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
            }
        }
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
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var categoriesSection: some View {
        LazyVGrid(columns: categoryColumns, spacing: 10) {
            ForEach(categories) { option in
                ZStack(alignment: .topTrailing) {
                    Button {
                        selectedCategory = option
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: option.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(option.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(minHeight: 30)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    if option.isCustom {
                        Menu {
                            Button("Редактировать") {
                                openCategoryEditor(for: option)
                            }
                            Button("Удалить", role: .destructive) {
                                pendingDeleteCategoryRaw = option.rawValue
                                showDeleteCategoryAlert = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                showCreateCategorySheet = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Добавить")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 92)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        )
                )
            }
            .buttonStyle(.plain)
        }
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

            guard !Task.isCancelled else { return }
            await MainActor.run {
                monthlyTotal = total
                isLoadingMonthlyTotal = false
            }
        }
    }

    private func handleCreateCategory(_ name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let created = viewModel.createCustomCategory(kind: kind.categoryKind, name: trimmedName, icon: icon) {
            selectedCategory = created
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
            if let created = viewModel.createCustomCategory(kind: kind.categoryKind, name: trimmedName, icon: icon) {
                selectedCategory = created
                searchText = ""
            }
        case .edit(let rawValue):
            guard viewModel.renameCustomCategory(
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

    private func formattedMonthlyTotal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: value)) ?? "0"
        return "\(amount) \(viewModel.state.displayCurrency)"
    }
}

private enum CashflowCategoryTransactionSheetKind {
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
    @Binding var name: String
    @Binding var icon: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool

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
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                                ForEach(CashflowCustomCategory.allowedIcons, id: \.self) { symbol in
                                    Button {
                                        icon = symbol
                                    } label: {
                                        Image(systemName: symbol)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(icon == symbol ? AppColors.textPrimary : AppColors.textSecondary)
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(icon == symbol ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                                            )
                                    }
                                    .buttonStyle(.plain)
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
