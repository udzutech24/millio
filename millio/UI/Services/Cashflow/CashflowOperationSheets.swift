//
//  CashflowOperationSheets.swift
//  millio
//
//  Created by Codex on 01.03.2026.
//

import SwiftUI

struct CashflowIncomeTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedCategory: CashflowCategoryOption?
    @State private var searchText: String = ""
    @State private var monthlyIncomeTotal: Double = 0
    @State private var isLoadingMonthlyIncomeTotal: Bool = false
    @State private var monthTotalTask: Task<Void, Never>?

    @State private var showCreateCategorySheet: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryIcon: String = CashflowCustomCategory.defaultIcon

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

    private var incomeCategories: [CashflowCategoryOption] {
        viewModel.categoryOptions(for: .income, matching: searchText)
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
            .navigationTitle("Новый доход")
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
                    transactionType: .income,
                    showsTransactionTypeSection: false,
                    showsCategorySection: false,
                    wrapsInNavigationStack: false,
                    showsDismissButton: false,
                    customNavigationTitle: "Новый доход",
                    preselectedIncomeCategoryRaw: option.rawValue,
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
            .onAppear {
                reloadMonthlyIncomeTotal()
            }
            .onChange(of: selectedMonth) { _, _ in
                reloadMonthlyIncomeTotal()
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
        FinancesGlassCard(accentColor: AppColors.incomeGradient.first) {
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
            FinancesSectionHeader(title: "Итого доход за месяц")
            FinancesGlassCard(accentColor: AppColors.incomeGradient.first) {
                HStack {
                    Text("Итого")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    if isLoadingMonthlyIncomeTotal {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .scaleEffect(0.9)
                    } else {
                        Text(formattedMonthlyIncome(monthlyIncomeTotal))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
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
            ForEach(incomeCategories) { option in
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

    private func reloadMonthlyIncomeTotal() {
        monthTotalTask?.cancel()
        monthTotalTask = Task {
            await MainActor.run {
                isLoadingMonthlyIncomeTotal = true
            }

            let total = await viewModel.monthlyIncomeTotal(
                for: selectedMonth,
                in: viewModel.state.displayCurrency
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                monthlyIncomeTotal = total
                isLoadingMonthlyIncomeTotal = false
            }
        }
    }

    private func handleCreateCategory(_ name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let created = viewModel.createCustomCategory(kind: .income, name: trimmedName, icon: icon) {
            selectedCategory = created
            searchText = ""
        }

        newCategoryName = ""
        newCategoryIcon = CashflowCustomCategory.defaultIcon
        showCreateCategorySheet = false
    }

    private func formattedMonthlyIncome(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: value)) ?? "0"
        return "\(amount) \(viewModel.state.displayCurrency)"
    }
}

struct CashflowExpenseTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel

    var body: some View {
        CashflowTransactionEditorView(
            viewModel: viewModel,
            transactionType: .expense,
            showsTransactionTypeSection: false,
            customNavigationTitle: "Новый расход"
        )
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
