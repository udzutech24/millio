//
//  MockDataGenerator.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Генератор моковых данных для разработки и тестирования
@MainActor
final class MockDataGenerator {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Очистить все данные (Card, Credit, Investment, CashflowTransaction)
    func clearAllData() throws {
        // Удаляем все карты
        let cardDescriptor = FetchDescriptor<Card>()
        let cards = try modelContext.fetch(cardDescriptor)
        for card in cards {
            modelContext.delete(card)
        }
        
        // Удаляем все кредиты
        let creditDescriptor = FetchDescriptor<Credit>()
        let credits = try modelContext.fetch(creditDescriptor)
        for credit in credits {
            modelContext.delete(credit)
        }
        
        // Удаляем все активы
        let investmentDescriptor = FetchDescriptor<Investment>()
        let investments = try modelContext.fetch(investmentDescriptor)
        for investment in investments {
            modelContext.delete(investment)
        }
        
        // Удаляем все транзакции кэшфлоу
        let transactionDescriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = try modelContext.fetch(transactionDescriptor)
        for transaction in transactions {
            modelContext.delete(transaction)
        }
        
        // Удаляем все FinanceAccount и FinanceGroup
        let accountDescriptor = FetchDescriptor<FinanceAccount>()
        let accounts = try modelContext.fetch(accountDescriptor)
        for account in accounts {
            modelContext.delete(account)
        }
        
        let groupDescriptor = FetchDescriptor<FinanceGroup>()
        let groups = try modelContext.fetch(groupDescriptor)
        for group in groups {
            modelContext.delete(group)
        }
        
        try modelContext.save()
    }
    
    /// Генерировать моковые данные
    func generateMockData() throws {
        // Очищаем существующие данные
        try clearAllData()
        
        // Генерируем карты
        let cards = generateCards()
        for card in cards {
            modelContext.insert(card)
        }
        
        // Генерируем кредиты
        let credits = generateCredits()
        for credit in credits {
            modelContext.insert(credit)
            // Обновляем остаток долга
            credit.updateRemainingAmount()
        }
        
        // Генерируем активы
        let investments = generateInvestments()
        for investment in investments {
            modelContext.insert(investment)
        }
        
        // Сохраняем карты, кредиты и активы перед генерацией транзакций
        try modelContext.save()
        
        // Создаем группы и распределяем счета по ним
        let groups = generateGroups()
        for group in groups {
            modelContext.insert(group)
        }
        try modelContext.save()
        
        // Распределяем карты, кредиты и активы по группам
        distributeAccountsToGroups(cards: cards, credits: credits, investments: investments, groups: groups)
        try modelContext.save()
        
        // Генерируем транзакции кэшфлоу
        let transactions = generateTransactions(cards: cards)
        for transaction in transactions {
            modelContext.insert(transaction)
        }
        
        // Обновляем балансы карт на основе транзакций
        updateCardBalances(cards: cards, transactions: transactions)
        
        try modelContext.save()
    }
    
    // MARK: - Private Methods
    
    private func generateCards() -> [Card] {
        let banks: [Bank] = [.sberbank, .vtb, .alfa, .tinkoff, .raiffeisen, .gazprombank, .otkritie, .rosbank, .other]
        let currencies = ["RUB", "USD", "EUR"]
        var cards: [Card] = []
        
        let calendar = Calendar.current
        let now = Date()
        // Устанавливаем дату создания карт на 13-14 месяцев назад,
        // чтобы они были созданы до начала периода транзакций (которые генерируются за последние 12 месяцев)
        let monthsAgo = Int.random(in: 13...14)
        guard let cardsCreatedDate = calendar.date(byAdding: .month, value: -monthsAgo, to: now) else {
            return cards
        }
        
        // Генерируем 12 карт
        for i in 0..<12 {
            let isDebit = i % 3 != 0 // Больше дебетовых
            let bank = banks[i % banks.count]
            let currency = currencies[i % currencies.count]
            let cardNumber = String(format: "%04d", 1000 + i)
            
            let balance: Double
            if isDebit {
                balance = Double.random(in: 5000...500000)
            } else {
                balance = Double.random(in: 0...100000)
            }
            
            let creditLimit = isDebit ? nil : Double.random(in: 100000...500000)
            
            let card = Card(
                name: "\(bank.displayName) \(isDebit ? "Дебетовая" : "Кредитная") \(cardNumber)",
                cardNumber: cardNumber,
                bank: bank,
                cardType: isDebit ? .debit : .credit,
                priority: i < 3 ? .high : (i < 6 ? .normal : .low),
                currency: currency,
                balance: balance,
                creditLimit: creditLimit,
                isFavorite: i < 2,
                includeInTotal: true
            )
            
            // Устанавливаем дату создания в прошлое, чтобы карты существовали до начала периода транзакций
            card.createdAt = cardsCreatedDate
            card.updatedAt = cardsCreatedDate
            
            cards.append(card)
        }
        
        return cards
    }
    
    private func generateCredits() -> [Credit] {
        let banks: [Bank] = [.sberbank, .vtb, .alfa, .tinkoff, .raiffeisen, .gazprombank, .otkritie, .rosbank]
        let creditTypes: [CreditType] = [.consumer, .mortgage, .auto, .refinancing, .other]
        var credits: [Credit] = []
        
        let calendar = Calendar.current
        let now = Date()
        
        // Генерируем 10 кредитов
        for i in 0..<10 {
            let bank = banks[i % banks.count]
            let creditType = creditTypes[i % creditTypes.count]
            let currency = i < 7 ? "RUB" : (i < 9 ? "USD" : "EUR")
            
            // Разные даты начала (от 1 месяца до 5 лет назад)
            let monthsAgo = Int.random(in: 1...60)
            guard let startDate = calendar.date(byAdding: .month, value: -monthsAgo, to: now) else { continue }
            
            // Срок кредита от 12 до 120 месяцев
            let termMonths = Int.random(in: 12...120)
            guard let endDate = calendar.date(byAdding: .month, value: termMonths, to: startDate) else { continue }
            
            // Сумма кредита
            let amount: Double
            switch creditType {
            case .mortgage:
                amount = Double.random(in: 2_000_000...15_000_000)
            case .auto:
                amount = Double.random(in: 500_000...5_000_000)
            default:
                amount = Double.random(in: 100_000...2_000_000)
            }
            
            // Процентная ставка
            let interestRate: Double
            switch creditType {
            case .mortgage:
                interestRate = Double.random(in: 7.0...12.0)
            case .auto:
                interestRate = Double.random(in: 8.0...15.0)
            default:
                interestRate = Double.random(in: 12.0...25.0)
            }
            
            // Рассчитываем ежемесячный платеж
            let monthlyPayment = Credit.calculateMonthlyPayment(
                amount: amount,
                annualInterestRate: interestRate,
                termMonths: termMonths
            )
            
            let credit = Credit(
                name: "\(creditType.displayName) \(bank.displayName)",
                amount: amount,
                interestRate: interestRate,
                monthlyPayment: monthlyPayment,
                startDate: startDate,
                termMonths: termMonths,
                currency: currency,
                bank: bank,
                creditType: creditType,
                endDate: endDate,
                includeInTotal: true
            )
            
            credits.append(credit)
        }
        
        return credits
    }
    
    private func generateInvestments() -> [Investment] {
        let categories: [InvestmentCategory] = [.car, .house, .stocks, .business, .crypto, .bonds, .metals, .other]
        let currencies = ["RUB", "USD", "EUR"]
        var investments: [Investment] = []
        
        let calendar = Calendar.current
        let now = Date()
        // Устанавливаем дату создания инвестиций на 13-14 месяцев назад,
        // чтобы они были созданы до начала периода транзакций
        let monthsAgo = Int.random(in: 13...14)
        guard let investmentsCreatedDate = calendar.date(byAdding: .month, value: -monthsAgo, to: now) else {
            return investments
        }
        
        // Генерируем 10 активов
        for i in 0..<10 {
            let category = categories[i % categories.count]
            let investmentType: InvestmentType = i < 7 ? .positive : .negative
            let currency = currencies[i % currencies.count]
            let priority: InvestmentPriority = i < 3 ? .high : (i < 6 ? .normal : .low)
            
            // Сумма зависит от категории
            let amount: Double
            switch category {
            case .house:
                amount = Double.random(in: 5_000_000...50_000_000)
            case .car:
                amount = Double.random(in: 500_000...5_000_000)
            case .stocks, .crypto, .bonds:
                amount = Double.random(in: 100_000...5_000_000)
            case .business:
                amount = Double.random(in: 1_000_000...20_000_000)
            case .metals:
                amount = Double.random(in: 50_000...2_000_000)
            default:
                amount = Double.random(in: 50_000...1_000_000)
            }
            
            let investment = Investment(
                name: "\(category.displayName) \(i + 1)",
                investmentType: investmentType,
                category: category,
                amount: amount,
                currency: currency,
                includeInTotal: true,
                priority: priority,
                isFavorite: i < 2
            )
            
            // Устанавливаем дату создания в прошлое, чтобы инвестиции существовали до начала периода транзакций
            investment.createdAt = investmentsCreatedDate
            investment.updatedAt = investmentsCreatedDate
            
            investments.append(investment)
        }
        
        return investments
    }
    
    private func generateTransactions(cards: [Card]) -> [CashflowTransaction] {
        var transactions: [CashflowTransaction] = []
        let calendar = Calendar.current
        let now = Date()
        
        // Генерируем транзакции за последние 12 месяцев
        guard let startDate = calendar.date(byAdding: .month, value: -12, to: now) else {
            return transactions
        }
        
        // Вычисляем количество дней между startDate и now
        let daysBetween = calendar.dateComponents([.day], from: startDate, to: now).day ?? 365
        
        let incomeCategories: [IncomeCategory] = [.salary, .freelance, .investment, .gift, .bonus, .other]
        let expenseCategories: [ExpenseCategory] = [.groceries, .cafe, .transport, .shopping, .entertainment, .bills, .health, .education, .other]
        
        // Генерируем ~500 транзакций
        for _ in 0..<500 {
            // Случайная дата между startDate и now
            let daysAgo = Int.random(in: 0...daysBetween)
            guard let transactionDate = calendar.date(byAdding: .day, value: -daysAgo, to: now),
                  transactionDate >= startDate else { continue }
            
            // Выбираем случайную карту
            guard let card = cards.randomElement() else { continue }
            
            // Тип транзакции (больше расходов)
            let transactionType: CashflowTransactionType
            let random = Int.random(in: 0...100)
            if random < 60 {
                transactionType = .expense
            } else if random < 85 {
                transactionType = .income
            } else if random < 95 {
                transactionType = .transfer
            } else {
                transactionType = .exchange
            }
            
            let transaction: CashflowTransaction
            
            switch transactionType {
            case .income:
                let category = incomeCategories.randomElement() ?? .other
                let amount = Double.random(in: 1000...50000)
                transaction = CashflowTransaction(
                    transactionType: .income,
                    amount: amount,
                    currency: card.currency,
                    transactionDate: transactionDate,
                    cardID: card.cardUniqueID,
                    incomeCategory: category,
                    note: "Моковый доход: \(category.displayName)"
                )
                
            case .expense:
                let category = expenseCategories.randomElement() ?? .other
                let amount = Double.random(in: 100...10000)
                transaction = CashflowTransaction(
                    transactionType: .expense,
                    amount: amount,
                    currency: card.currency,
                    transactionDate: transactionDate,
                    cardID: card.cardUniqueID,
                    expenseCategory: category,
                    note: "Моковый расход: \(category.displayName)"
                )
                
            case .transfer:
                guard let toCard = cards.filter({ $0.cardUniqueID != card.cardUniqueID }).randomElement() else { continue }
                let amount = Double.random(in: 500...20000)
                transaction = CashflowTransaction(
                    transactionType: .transfer,
                    amount: amount,
                    currency: card.currency,
                    transactionDate: transactionDate,
                    cardID: card.cardUniqueID,
                    toCardID: toCard.cardUniqueID,
                    note: "Моковый перевод"
                )
                
            case .exchange:
                let fromCurrency = card.currency
                let toCurrency = ["RUB", "USD", "EUR"].first(where: { $0 != fromCurrency }) ?? "USD"
                let fromAmount = Double.random(in: 1000...50000)
                // Простой курс обмена (примерный)
                let exchangeRate: Double
                if fromCurrency == "RUB" && toCurrency == "USD" {
                    exchangeRate = 0.011
                } else if fromCurrency == "USD" && toCurrency == "RUB" {
                    exchangeRate = 90.0
                } else if fromCurrency == "RUB" && toCurrency == "EUR" {
                    exchangeRate = 0.010
                } else if fromCurrency == "EUR" && toCurrency == "RUB" {
                    exchangeRate = 100.0
                } else {
                    exchangeRate = 1.0
                }
                let toAmount = fromAmount * exchangeRate
                
                transaction = CashflowTransaction(
                    transactionType: .exchange,
                    amount: fromAmount,
                    currency: fromCurrency,
                    transactionDate: transactionDate,
                    cardID: card.cardUniqueID,
                    exchangeFromCurrency: fromCurrency,
                    exchangeToCurrency: toCurrency,
                    exchangeFromAmount: fromAmount,
                    exchangeToAmount: toAmount,
                    note: "Моковый обмен валют"
                )
            }
            
            transactions.append(transaction)
        }
        
        // Сортируем по дате
        return transactions.sorted { $0.transactionDate > $1.transactionDate }
    }
    
    private func updateCardBalances(cards: [Card], transactions: [CashflowTransaction]) {
        // Создаем словарь для отслеживания балансов
        // Важно: используем начальный баланс карты (который был при создании), а не текущий
        var balances: [String: Double] = [:]
        var initialBalances: [String: Double] = [:]
        
        // Сохраняем начальные балансы карт (которые были при создании)
        for card in cards {
            initialBalances[card.cardUniqueID] = card.balance
            balances[card.cardUniqueID] = card.balance
        }
        
        // Обрабатываем транзакции в хронологическом порядке
        let sortedTransactions = transactions.sorted { $0.transactionDate < $1.transactionDate }
        
        for transaction in sortedTransactions {
            switch transaction.transactionType {
            case .income:
                if let cardID = transaction.cardID {
                    balances[cardID, default: 0] += transaction.amount
                }
                
            case .expense:
                if let cardID = transaction.cardID {
                    balances[cardID, default: 0] = max(0, balances[cardID, default: 0] - transaction.amount)
                }
                
            case .transfer:
                if let fromCardID = transaction.cardID,
                   let toCardID = transaction.toCardID {
                    balances[fromCardID, default: 0] = max(0, balances[fromCardID, default: 0] - transaction.amount)
                    balances[toCardID, default: 0] += transaction.amount
                }
                
            case .exchange:
                // Для обмена валют просто обновляем баланс карты
                if let cardID = transaction.cardID {
                    // Уменьшаем сумму "из"
                    if let fromAmount = transaction.exchangeFromAmount {
                        balances[cardID, default: 0] = max(0, balances[cardID, default: 0] - fromAmount)
                    }
                    // Увеличиваем сумму "в" (упрощенная логика)
                    if let toAmount = transaction.exchangeToAmount {
                        balances[cardID, default: 0] += toAmount
                    }
                }
            }
        }
        
        // Обновляем балансы карт
        for card in cards {
            if let newBalance = balances[card.cardUniqueID] {
                card.balance = newBalance
                card.updatedAt = Date()
            }
        }
    }
    
    /// Генерировать группы финансов
    private func generateGroups() -> [FinanceGroup] {
        let groupConfigs: [(name: String, colorHex: String, priority: GroupPriority, isFavorite: Bool)] = [
            ("Основные карты", "#007AFF", .high, true),      // Синий
            ("Кредиты", "#FF3B30", .normal, false),          // Красный
            ("Инвестиции", "#34C759", .normal, false),       // Зеленый
            ("Резерв", "#FF9500", .low, false),              // Оранжевый
            ("Бизнес", "#5856D6", .normal, false)            // Фиолетовый
        ]
        
        var groups: [FinanceGroup] = []
        for (index, config) in groupConfigs.enumerated() {
            let group = FinanceGroup(
                name: config.name,
                colorHex: config.colorHex,
                order: index,
                isFavorite: config.isFavorite,
                priority: config.priority
            )
            groups.append(group)
        }
        
        return groups
    }
    
    /// Распределить счета по группам
    private func distributeAccountsToGroups(
        cards: [Card],
        credits: [Credit],
        investments: [Investment],
        groups: [FinanceGroup]
    ) {
        guard let mainCardsGroup = groups.first(where: { $0.name == "Основные карты" }),
              let creditsGroup = groups.first(where: { $0.name == "Кредиты" }),
              let investmentsGroup = groups.first(where: { $0.name == "Инвестиции" }),
              let reserveGroup = groups.first(where: { $0.name == "Резерв" }),
              let businessGroup = groups.first(where: { $0.name == "Бизнес" }) else {
            return
        }
        
        // Распределяем карты: первые 4 в "Основные карты", следующие 4 в "Резерв", остальные в "Бизнес"
        for (index, card) in cards.enumerated() {
            let targetGroup: FinanceGroup
            if index < 4 {
                targetGroup = mainCardsGroup
            } else if index < 8 {
                targetGroup = reserveGroup
            } else {
                targetGroup = businessGroup
            }
            
            let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
            account.group = targetGroup
            modelContext.insert(account)
        }
        
        // Распределяем кредиты: все в группу "Кредиты"
        for credit in credits {
            let account = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
            account.group = creditsGroup
            modelContext.insert(account)
        }
        
        // Распределяем активы: первые 5 в "Инвестиции", остальные в "Бизнес"
        for (index, investment) in investments.enumerated() {
            let targetGroup: FinanceGroup = index < 5 ? investmentsGroup : businessGroup
            
            let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
            account.group = targetGroup
            modelContext.insert(account)
        }
    }
}
