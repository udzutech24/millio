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
    @State private var exchangeFromCurrency: String = "RUB"
    @State private var exchangeToCurrency: String = "USD"
    @State private var exchangeFromAmountText: String = ""
    @State private var exchangeToAmountText: String = ""
    @State private var isCalculatingExchange: Bool = false
    @State private var note: String = ""
    @State private var availableCurrencies: [String] = []
    @State private var isLoadingCurrencies: Bool = false
    
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
            _exchangeFromCurrency = State(initialValue: transaction.exchangeFromCurrency ?? "RUB")
            _exchangeToCurrency = State(initialValue: transaction.exchangeToCurrency ?? "USD")
            _exchangeFromAmountText = State(initialValue: transaction.exchangeFromAmount.map { formatNumberForDisplay($0) } ?? "")
            _exchangeToAmountText = State(initialValue: transaction.exchangeToAmount.map { formatNumberForDisplay($0) } ?? "")
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
                                    ForEach(viewModel.state.availableCards) { card in
                                        Text(card.name).tag(card.cardUniqueID)
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)
                                
                                Picker("На карту", selection: Binding(
                                    get: { selectedToCardID ?? "" },
                                    set: { selectedToCardID = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("Выберите карту").tag("")
                                    ForEach(viewModel.state.availableCards) { card in
                                        Text(card.name).tag(card.cardUniqueID)
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)
                            }
                        } header: {
                            Text("Перевод")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedTransactionType == .exchange {
                        Section {
                            if isLoadingCurrencies {
                                HStack {
                                    Text("Валюта из")
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(AppColors.textTertiary)
                                }
                            } else {
                                Picker("Валюта из", selection: $exchangeFromCurrency) {
                                    ForEach(availableCurrencies, id: \.self) { currency in
                                        Text(currency).tag(currency)
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)
                                .onChange(of: exchangeFromCurrency) { oldValue, newValue in
                                    calculateExchange()
                                }
                                
                                TextField("Сумма", text: Binding(
                                    get: { formatNumberForDisplay(exchangeFromAmountText) },
                                    set: { newValue in
                                        let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                            .replacingOccurrences(of: ",", with: ".")
                                        exchangeFromAmountText = normalized
                                        calculateExchange()
                                    }
                                ))
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                            }
                            
                            if isLoadingCurrencies {
                                HStack {
                                    Text("Валюта в")
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(AppColors.textTertiary)
                                }
                            } else {
                                Picker("Валюта в", selection: $exchangeToCurrency) {
                                    ForEach(availableCurrencies, id: \.self) { currency in
                                        Text(currency).tag(currency)
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)
                                .onChange(of: exchangeToCurrency) { oldValue, newValue in
                                    calculateExchange()
                                }
                                
                                if isCalculatingExchange {
                                    HStack {
                                        Text("Сумма")
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(AppColors.textTertiary)
                                    }
                                } else {
                                    TextField("Сумма", text: Binding(
                                        get: { formatNumberForDisplay(exchangeToAmountText) },
                                        set: { newValue in
                                            let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                                .replacingOccurrences(of: ",", with: ".")
                                            exchangeToAmountText = normalized
                                        }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .disabled(true)
                                }
                            }
                            
                            DatePicker("Дата", selection: $transactionDate, displayedComponents: .date)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Обмен валют")
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
            return selectedCardID != nil
        case .transfer:
            return selectedCardID != nil && selectedToCardID != nil && selectedCardID != selectedToCardID
        case .exchange:
            guard !exchangeFromAmountText.isEmpty,
                  let fromAmount = Double(exchangeFromAmountText.replacingOccurrences(of: ",", with: ".")),
                  fromAmount > 0,
                  !exchangeToAmountText.isEmpty,
                  let toAmount = Double(exchangeToAmountText.replacingOccurrences(of: ",", with: ".")),
                  toAmount > 0,
                  exchangeFromCurrency != exchangeToCurrency else {
                return false
            }
            return true
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
        case .exchange:
            return AppColors.coursesGradient
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
        
        if selectedTransactionType == .exchange {
            transaction.exchangeFromCurrency = exchangeFromCurrency
            transaction.exchangeToCurrency = exchangeToCurrency
            transaction.exchangeFromAmount = Double(exchangeFromAmountText.replacingOccurrences(of: ",", with: "."))
            transaction.exchangeToAmount = Double(exchangeToAmountText.replacingOccurrences(of: ",", with: "."))
            transaction.amount = transaction.exchangeFromAmount ?? 0.0
            transaction.currency = exchangeFromCurrency
        }
        
        transaction.note = note.isEmpty ? nil : note
        
        viewModel.handle(.updateTransaction(transaction))
        dismiss()
    }
    
    private func calculateExchange() {
        guard !exchangeFromAmountText.isEmpty,
              let fromAmount = Double(exchangeFromAmountText.replacingOccurrences(of: ",", with: ".")),
              fromAmount > 0,
              exchangeFromCurrency != exchangeToCurrency else {
            exchangeToAmountText = ""
            return
        }
        
        isCalculatingExchange = true
        
        Task {
            if let converted = await CurrencyRateService.shared.convert(
                amount: fromAmount,
                from: exchangeFromCurrency,
                to: exchangeToCurrency
            ) {
                await MainActor.run {
                    exchangeToAmountText = String(converted)
                    isCalculatingExchange = false
                }
            } else {
                await MainActor.run {
                    exchangeToAmountText = ""
                    isCalculatingExchange = false
                }
            }
        }
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
}
