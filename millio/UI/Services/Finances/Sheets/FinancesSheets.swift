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
    @State private var searchText: String = ""
    
    // Используем полный список валют из CurrencySelectionSupport
    private let allCurrencies = CurrencySelectionSupport.allCodes(includeCrypto: false)
    
    var body: some View {
        NavigationStack {
            CurrencyPickerView(
                allCodes: allCurrencies,
                searchText: $searchText,
                selectedCodes: [], // Можно добавить закрепленные, если нужно
                favoriteCodes: [], // Можно подключить избранное из настроек, если есть доступ
                currentSelection: isSecondary ? viewModel.state.secondaryDisplayCurrency : viewModel.state.displayCurrency,
                onToggleFavorite: nil,
                onSelect: { currency in
                    if isSecondary {
                        viewModel.handle(.setSecondaryDisplayCurrency(currency))
                    } else {
                        viewModel.handle(.setDisplayCurrency(currency))
                    }
                    dismiss()
                }
            )
            .navigationTitle(isSecondary ? "Дополнительная валюта" : "Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Настройки цели
                        VStack(alignment: .leading, spacing: 10) {
                            FinancesSectionHeader(title: "Настройки цели")
                            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                                Toggle("Включить цель накопления", isOn: $isEnabled)
                                    .tint(AppColors.toggleOnGreen)
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                        }
                        
                        if isEnabled {
                            // Сумма цели
                            VStack(alignment: .leading, spacing: 10) {
                                FinancesSectionHeader(title: "Сумма цели (\(viewModel.state.displayCurrency))")
                                FinancesGlassCard {
                                    TextField("Сумма цели", text: $goalAmount)
                                        .keyboardType(.decimalPad)
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.vertical, 14)
                                        .padding(.horizontal, 16)
                                }
                            }
                            
                            // Прогресс
                            if let amount = Double(goalAmount), amount > 0 {
                                let progress: Double = {
                                    guard amount > 0 else { return 0.0 }
                                    let calculated = viewModel.state.totalAmount / amount
                                    guard calculated.isFinite else { return 0.0 }
                                    return max(0.0, min(1.0, calculated))
                                }()
                                let remaining = max(0, amount - viewModel.state.totalAmount)
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    FinancesSectionHeader(title: "Прогресс")
                                    FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                                        VStack(alignment: .leading, spacing: 16) {
                                            VStack(spacing: 8) {
                                                HStack {
                                                    Text("Текущая сумма")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundStyle(AppColors.textSecondary)
                                                    Spacer()
                                                    Text("\(formatAmount(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden)) \(viewModel.state.displayCurrency)")
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundStyle(AppColors.textPrimary)
                                                }
                                                
                                                HStack {
                                                    Text("Осталось накопить")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundStyle(AppColors.textSecondary)
                                                    Spacer()
                                                    Text("\(formatAmount(remaining, isHidden: viewModel.state.isAmountHidden)) \(viewModel.state.displayCurrency)")
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundStyle(AppColors.textPrimary)
                                                }
                                            }
                                            
                                            // Кастомный прогресс бар
                                            VStack(spacing: 8) {
                                                GeometryReader { proxy in
                                                    ZStack(alignment: .leading) {
                                                        Capsule()
                                                            .fill(Color.white.opacity(0.1))
                                                            .frame(height: 8)
                                                        
                                                        Capsule()
                                                            .fill(LinearGradient(colors: AppColors.financesGradient, startPoint: .leading, endPoint: .trailing))
                                                            .frame(width: max(0, min(proxy.size.width, proxy.size.width * progress)), height: 8)
                                                    }
                                                }
                                                .frame(height: 8)
                                                
                                                Text("Выполнено: \(Int(progress * 100))%")
                                                    .font(.system(size: 12, weight: .regular))
                                                    .foregroundStyle(AppColors.textTertiary)
                                                    .frame(maxWidth: .infinity, alignment: .center)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
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
