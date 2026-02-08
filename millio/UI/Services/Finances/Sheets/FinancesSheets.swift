//
//  FinancesSheets.swift
//  millio
//

import SwiftUI

// MARK: - Sheets Modifier

struct SheetsModifier: ViewModifier {
    @ObservedObject var viewModel: FinanceViewModel
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { viewModel.state.showGroupEditor },
                set: { if !$0 { viewModel.handle(.hideGroupEditor) } }
            )) {
                FinanceGroupEditorView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showAddAccountSheet },
                set: { if !$0 { viewModel.handle(.hideAddAccountSheet) } }
            )) {
                FinanceAddAccountView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showCreateCardSheet },
                set: { if !$0 { viewModel.handle(.hideCreateCardSheet) } }
            )) {
                FinanceCreateCardView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showCreateCreditSheet },
                set: { if !$0 { viewModel.handle(.hideCreateCreditSheet) } }
            )) {
                FinanceCreateCreditView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showCreateInvestmentSheet },
                set: { if !$0 { viewModel.handle(.hideCreateInvestmentSheet) } }
            )) {
                FinanceCreateInvestmentView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showDisplayCurrencySheet },
                set: { if !$0 { viewModel.handle(.hideDisplayCurrencySheet) } }
            )) {
                DisplayCurrencySheet(viewModel: viewModel, isSecondary: false)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showSecondaryDisplayCurrencySheet },
                set: { if !$0 { viewModel.handle(.hideSecondaryDisplayCurrencySheet) } }
            )) {
                DisplayCurrencySheet(viewModel: viewModel, isSecondary: true)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showEditCardSheet },
                set: { if !$0 { viewModel.handle(.hideEditCardSheet) } }
            )) {
                if let cardID = viewModel.state.editingCardID,
                   let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                    FinanceEditCardView(card: card, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showEditCreditSheet },
                set: { if !$0 { viewModel.handle(.hideEditCreditSheet) } }
            )) {
                if let creditID = viewModel.state.editingCreditID,
                   let credit = viewModel.state.availableCredits.first(where: { $0.creditUniqueID == creditID }) {
                    FinanceEditCreditView(credit: credit, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showEditInvestmentSheet },
                set: { if !$0 { viewModel.handle(.hideEditInvestmentSheet) } }
            )) {
                if let investmentID = viewModel.state.editingInvestmentID,
                   let investment = viewModel.state.availableInvestments.first(where: { $0.investmentUniqueID == investmentID }) {
                    FinanceEditInvestmentView(investment: investment, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showQuickEditAccountSheet },
                set: { if !$0 { viewModel.handle(.hideQuickEditAccountSheet) } }
            )) {
                if let account = viewModel.state.quickEditAccount {
                    FinanceQuickEditAccountView(account: account, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showGroupDynamics },
                set: { if !$0 { viewModel.handle(.hideGroupDynamics) } }
            )) {
                if let group = viewModel.state.selectedGroupForDynamics {
                    FinanceDynamicsView(
                        financeViewModel: viewModel,
                        initialGroupID: group.groupUniqueID,
                        initialGroupCurrency: group.displayCurrency
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showAccountDynamics },
                set: { if !$0 { viewModel.handle(.hideAccountDynamics) } }
            )) {
                if let account = viewModel.state.selectedAccountForDynamics {
                    FinanceDynamicsView(
                        financeViewModel: viewModel,
                        initialAccountID: account.accountUniqueID,
                        initialAccountCurrency: viewModel.getAccountInfo(account: account)?.currency,
                        initialAccount: account
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showSavingsGoalSheet },
                set: { if !$0 { viewModel.handle(.hideSavingsGoalSheet) } }
            )) {
                SavingsGoalSettingsView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
    }
}

// MARK: - Display Currency Sheet

struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    var isSecondary: Bool = false
    @State private var availableCurrencies: [String] = []
    @State private var filteredCurrencies: [String] = []
    @State private var searchText: String = ""
    @State private var isLoading = true
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
            TextField("Поиск валют", text: $searchText)
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if isLoading {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                } else {
                    VStack(spacing: 0) {
                        searchBar
                        
                        List {
                            ForEach(filteredCurrencies, id: \.self) { currency in
                                Button {
                                    if isSecondary {
                                        viewModel.handle(.setSecondaryDisplayCurrency(currency))
                                    } else {
                                        viewModel.handle(.setDisplayCurrency(currency))
                                    }
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(currency)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        if isSecondary {
                                            if viewModel.state.secondaryDisplayCurrency == currency {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: AppColors.financesGradient,
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                            }
                                        } else {
                                            if viewModel.state.displayCurrency == currency {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: AppColors.financesGradient,
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                            }
                                        }
                                    }
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(isSecondary ? "Дополнительная валюта" : "Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.financesGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .task { await loadAvailableCurrencies() }
            .onChange(of: searchText) { _, _ in filterCurrencies() }
        }
    }
    
    private func loadAvailableCurrencies() async {
        isLoading = true
        defer { isLoading = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        
        let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
        let fromAccounts = Set(
            viewModel.state.availableCards.map { $0.currency } +
            viewModel.state.availableCredits.map { $0.currency } +
            viewModel.state.availableInvestments.map { $0.currency }
        )
        availableCurrencies = Array(fromRateSource.union(fromAccounts)).sorted()
        filteredCurrencies = availableCurrencies
    }
    
    private func filterCurrencies() {
        if searchText.isEmpty {
            filteredCurrencies = availableCurrencies
        } else {
            filteredCurrencies = availableCurrencies.filter { currency in
                currency.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - Savings Goal Settings View

struct SavingsGoalSettingsView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isEnabled: Bool = false
    @State private var goalAmount: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        Toggle("Включить цель накопления", isOn: $isEnabled)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Настройки цели")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    if isEnabled {
                        Section {
                            TextField("Сумма цели", text: $goalAmount)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Сумма цели (\(viewModel.state.displayCurrency))")
                                .foregroundStyle(AppColors.textSecondary)
                        } footer: {
                            if let amount = Double(goalAmount), amount > 0 {
                                let progress: Double = {
                                    guard amount > 0 else { return 0.0 }
                                    let calculated = viewModel.state.totalAmount / amount
                                    guard calculated.isFinite else { return 0.0 }
                                    return max(0.0, min(1.0, calculated))
                                }()
                                let remaining = max(0, amount - viewModel.state.totalAmount)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Текущая сумма: \(formatAmount(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden)) \(viewModel.state.displayCurrency)")
                                    Text("Осталось накопить: \(formatAmount(remaining, isHidden: viewModel.state.isAmountHidden)) \(viewModel.state.displayCurrency)")
                                    
                                    ProgressView(value: progress)
                                        .tint(AppColors.financesGradient.first ?? AppColors.brandPrimary)
                                    
                                    Text("Прогресс: \(Int(progress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Цель накопления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        viewModel.handle(.setSavingsGoalEnabled(isEnabled))
                        if let amount = Double(goalAmount) {
                            viewModel.handle(.setSavingsGoalAmount(amount))
                        }
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            .onAppear {
                isEnabled = viewModel.state.isSavingsGoalEnabled
                if viewModel.state.savingsGoalAmount > 0 {
                    goalAmount = String(format: "%.2f", viewModel.state.savingsGoalAmount)
                }
            }
        }
    }
    
    private func formatAmount(_ amount: Double, isHidden: Bool = false) -> String {
        if isHidden {
            let digits = Int(amount.rounded())
            let digitCount = String(digits).count
            return String(repeating: "•", count: max(3, digitCount))
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}
