//
//  CashflowTransactionEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

struct CashflowTransactionEditorView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let transactionType: CashflowTransactionType?
    let editingTransaction: CashflowTransaction?
    
    @State private var selectedTransactionType: CashflowTransactionType
    @State private var amountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var transactionDate: Date = Date()
    @State private var selectedCardID: String? = nil
    @State private var selectedToCardID: String? = nil
    @State private var selectedIncomeCategory: IncomeCategory? = nil
    @State private var selectedExpenseCategory: ExpenseCategory? = nil
    @State private var note: String = ""
    @State private var availableCurrencies: [String] = []
    @State private var isLoadingCurrencies: Bool = false
    @State private var isAmountOverBalance: Bool = false
    @State private var validationTask: Task<Void, Never>? = nil
    
    init(viewModel: CashflowViewModel, transactionType: CashflowTransactionType? = nil, transaction: CashflowTransaction? = nil) {
        self.viewModel = viewModel
        self.transactionType = transactionType
        self.editingTransaction = transaction
        
        if let transaction = transaction {
            _selectedTransactionType = State(initialValue: transaction.transactionType)
            _amountText = State(initialValue: formatNumberForDisplay(transaction.amount))
            _selectedCurrency = State(initialValue: transaction.currency)
            _transactionDate = State(initialValue: transaction.transactionDate)
            _selectedCardID = State(initialValue: transaction.cardID)
            _selectedToCardID = State(initialValue: transaction.toCardID)
            _selectedIncomeCategory = State(initialValue: transaction.incomeCategory)
            _selectedExpenseCategory = State(initialValue: transaction.expenseCategory)
            _note = State(initialValue: transaction.note ?? "")
        } else if let type = transactionType {
            _selectedTransactionType = State(initialValue: type)
            if type == .income {
                _selectedIncomeCategory = State(initialValue: .salary)
            } else if type == .expense {
                _selectedExpenseCategory = State(initialValue: .groceries)
            }
        } else {
            _selectedTransactionType = State(initialValue: .expense)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    // Тип транзакции (только для новых)
                    if editingTransaction == nil {
                        Section {
                            Picker("Тип операции", selection: $selectedTransactionType) {
                                ForEach(CashflowTransactionType.allCases, id: \.self) { type in
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.displayName)
                                    }
                                    .tag(type)
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                            .onChange(of: selectedTransactionType) { oldValue, newValue in
                                // Сбрасываем категории при смене типа
                                if newValue == .income {
                                    selectedIncomeCategory = .salary
                                    selectedExpenseCategory = nil
                                } else if newValue == .expense {
                                    selectedExpenseCategory = .groceries
                                    selectedIncomeCategory = nil
                                } else {
                                    selectedIncomeCategory = nil
                                    selectedExpenseCategory = nil
                                }
                            }
                        } header: {
                            Text("Тип операции")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    
                    // Категория
                    if selectedTransactionType == .income {
                        Section {
                            Picker("Категория дохода", selection: Binding(
                                get: { selectedIncomeCategory ?? .salary },
                                set: { selectedIncomeCategory = $0 }
                            )) {
                                ForEach(IncomeCategory.allCases, id: \.self) { category in
                                    HStack {
                                        Image(systemName: category.icon)
                                        Text(category.displayName)
                                    }
                                    .tag(category)
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Категория")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedTransactionType == .expense {
                        Section {
                            Picker("Категория расхода", selection: Binding(
                                get: { selectedExpenseCategory ?? .groceries },
                                set: { selectedExpenseCategory = $0 }
                            )) {
                                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                                    HStack {
                                        Image(systemName: category.icon)
                                        Text(category.displayName)
                                    }
                                    .tag(category)
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Категория")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    
                    // Основная информация
                    Section {
                        TextField("Сумма", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        
                        if isLoadingCurrencies {
                            HStack {
                                Text("Валюта")
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(AppColors.textTertiary)
                            }
                        } else {
                            Picker("Валюта", selection: $selectedCurrency) {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Text(currency).tag(currency)
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        DatePicker("Дата", selection: $transactionDate, displayedComponents: .date)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    // Карта
                    if selectedTransactionType == .income || selectedTransactionType == .expense {
                        Section {
                            if viewModel.state.availableCards.isEmpty {
                                Text("Нет доступных карт")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                            } else {
                                Picker("Карта", selection: Binding(
                                    get: { selectedCardID ?? "" },
                                    set: { selectedCardID = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("Выберите карту").tag("")
                                    ForEach(viewModel.state.availableCards) { card in
                                        Text(card.name).tag(card.cardUniqueID)
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)
                                
                                if shouldValidateBalance, let availableText = availableBalanceText {
                                    Text(availableText)
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                
                                if isAmountOverBalance {
                                    Text("Недостаточно средств")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.error)
                                }
                            }
                        } header: {
                            Text("Карта")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedTransactionType == .transfer {
                        Section {
                            if viewModel.state.availableCards.isEmpty {
                                Text("Нет доступных карт")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                            } else {
                                Picker("С карты", selection: Binding(
                                    get: { selectedCardID ?? "" },
                                    set: { selectedCardID = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("Выберите карту").tag("")
                                    ForEach(viewModel.state.availableCards.filter { $0.cardUniqueID != selectedToCardID }) { card in
                                        Text(card.name).tag(card.cardUniqueID)
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)

                                if shouldValidateBalance, let availableText = availableBalanceText {
                                    Text(availableText)
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                
                                if isAmountOverBalance {
                                    Text("Недостаточно средств")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.error)
                                }
                                
                                Picker("На карту", selection: Binding(
                                    get: { selectedToCardID ?? "" },
                                    set: { selectedToCardID = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("Выберите карту").tag("")
                                    ForEach(viewModel.state.availableCards.filter { $0.cardUniqueID != selectedCardID }) { card in
                                        Text(card.name).tag(card.cardUniqueID)
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)
                            }
                        } header: {
                            Text("Перевод")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    
                    // Комментарий
                    Section {
                        TextField("Комментарий", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Дополнительно")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(editingTransaction == nil ? "Новая операция" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveTransaction()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: getGradientColors(),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }
            }
            .onAppear {
                loadAvailableCurrencies()
                // Предвыбираем первую карту, если карта не выбрана
                if selectedCardID == nil && !viewModel.state.availableCards.isEmpty {
                    selectedCardID = viewModel.state.availableCards.first?.cardUniqueID
                }
                validateAvailableBalance()
            }
            .onChange(of: selectedCardID) { _, _ in
                if selectedCardID == selectedToCardID {
                    selectedToCardID = nil
                }
                validateAvailableBalance()
            }
            .onChange(of: selectedToCardID) { _, _ in
                if selectedToCardID == selectedCardID {
                    selectedToCardID = nil
                }
            }
            .onChange(of: selectedCurrency) { _, _ in
                validateAvailableBalance()
            }
            .onChange(of: amountText) { _, _ in
                validateAvailableBalance()
            }
            .onChange(of: transactionDate) { _, _ in
                validateAvailableBalance()
            }
            .onChange(of: selectedTransactionType) { _, _ in
                validateAvailableBalance()
            }
        }
    }
    
    private var isValid: Bool {
        guard !amountText.isEmpty,
              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            return false
        }
        
        switch selectedTransactionType {
        case .income, .expense:
            return selectedCardID != nil && !isAmountOverBalance
        case .transfer:
            return selectedCardID != nil && selectedToCardID != nil && selectedCardID != selectedToCardID && !isAmountOverBalance
        case .balanceAdjustment, .cardBalanceAdjustment:
            // Ручное изменение баланса возможно для карт/инвестиций (и legacy для кредитов)
            return selectedCardID != nil || editingTransaction?.creditID != nil || editingTransaction?.investmentID != nil
        case .creditDebtAdjustment:
            // Корректировка долга может относиться к карте или кредиту
            return selectedCardID != nil || editingTransaction?.creditID != nil
        }
    }
    
    private func getGradientColors() -> [Color] {
        switch selectedTransactionType {
        case .income:
            return AppColors.incomeGradient
        case .expense:
            return AppColors.expenseGradient
        case .transfer:
            return AppColors.cashflowGradient
        case .balanceAdjustment:
            return AppColors.cardIndexGradient
        case .cardBalanceAdjustment:
            return AppColors.cardIndexGradient
        case .creditDebtAdjustment:
            return AppColors.creditsGradient
        }
    }
    
    private func saveTransaction() {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            return
        }
        
        let transaction: CashflowTransaction
        if let editing = editingTransaction {
            transaction = editing
        } else {
            transaction = CashflowTransaction(
                transactionType: selectedTransactionType,
                amount: amount,
                currency: selectedCurrency,
                transactionDate: transactionDate,
                cardID: selectedCardID,
                toCardID: selectedToCardID,
                incomeCategory: selectedIncomeCategory,
                expenseCategory: selectedExpenseCategory,
                note: note.isEmpty ? nil : note
            )
        }
        
        // Обновляем поля
        transaction.transactionTypeRaw = selectedTransactionType.rawValue
        transaction.amount = amount
        transaction.currency = selectedCurrency
        transaction.transactionDate = transactionDate
        transaction.cardID = selectedCardID
        transaction.toCardID = selectedToCardID
        transaction.incomeCategoryRaw = selectedIncomeCategory?.rawValue
        transaction.expenseCategoryRaw = selectedExpenseCategory?.rawValue
        transaction.note = note.isEmpty ? nil : note
        
        viewModel.handle(.updateTransaction(transaction))
        dismiss()
    }
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            
            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) {
                currencies.append(selectedCurrency)
            }
            availableCurrencies = currencies.sorted()
        }
    }
    
    private func formatNumberForDisplay(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    
    private func formatNumberForDisplay(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        let normalized = value.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        
        if let doubleValue = Double(normalized) {
            return formatNumberForDisplay(doubleValue)
        }
        
        return value
    }

    private var shouldValidateBalance: Bool {
        selectedTransactionType == .expense || selectedTransactionType == .transfer
    }
    
    private var availableBalanceText: String? {
        guard shouldValidateBalance,
              let cardID = selectedCardID,
              let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID }) else {
            return nil
        }
        
        let formatted = formatNumberForDisplay(card.balance)
        return "Доступно: \(formatted) \(card.currency)"
    }
    
    private func parseAmount() -> Double? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    private func validateAvailableBalance() {
        guard shouldValidateBalance,
              let cardID = selectedCardID,
              let amount = parseAmount(),
              amount > 0 else {
            isAmountOverBalance = false
            return
        }
        
        let currency = selectedCurrency
        let card = cardID
        let date = transactionDate
        
        validationTask?.cancel()
        validationTask = Task {
            do {
                let isAvailable = try await viewModel.isAmountAvailable(
                    amount: amount,
                    currency: currency,
                    fromCardID: card,
                    on: date
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isAmountOverBalance = !isAvailable
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isAmountOverBalance = false
                }
            }
            validationTask = nil
        }
    }
}
