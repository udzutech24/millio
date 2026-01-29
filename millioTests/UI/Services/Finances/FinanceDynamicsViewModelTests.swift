//
//  FinanceDynamicsViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 29.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@MainActor
final class MockDynamicsCurrencyRateService: CurrencyRateServiceProtocol {
    func getRate(from: String, to: String) async -> Double? { 1.0 }
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? { 1.0 }
    func convert(amount: Double, from: String, to: String) async -> Double? { amount }
    func forceRefreshRates() async {}
}

@Suite(.serialized)
@MainActor
struct FinanceDynamicsViewModelTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            HistoricalRate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.delete(model: FinanceAccount.self)
        try context.delete(model: FinanceGroup.self)
        try context.delete(model: CashflowTransaction.self)
        try context.delete(model: Investment.self)
        try context.delete(model: Credit.self)
        try context.delete(model: Card.self)
        try context.delete(model: HistoricalRate.self)
        try context.save()
        return context
    }

    @Test("Ручная корректировка долга учитывается в динамике без транзакций")
    func testManualAdjustmentAffectsDynamicsWhenNoTransactions() async throws {
        let modelContext = try createTestModelContext()

        let credit = Credit(
            name: "Кредит",
            amount: 100_000.0,
            interestRate: 0.0,
            monthlyPayment: 1_000.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.initialRemainingAmount = 100_000.0
        credit.hasInitialRemainingAmount = true
        credit.remainingAmount = 50_000.0
        credit.remainingAmountAdjustment = -50_000.0
        credit.updatedAt = Date()
        modelContext.insert(credit)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let endAmount = await dynamicsViewModel.calculateCreditRemainingAmount(
            credit: credit,
            at: Date(),
            accountCurrency: "RUB"
        )
        let startAmount = await dynamicsViewModel.calculateCreditRemainingAmount(
            credit: credit,
            at: credit.updatedAt.addingTimeInterval(-3600),
            accountCurrency: "RUB"
        )

        #expect(abs(endAmount - 50_000.0) < 0.01)
        #expect(abs(startAmount - 100_000.0) < 0.01)
    }

    @Test("Актуальный остаток учитывается даже при неполной истории транзакций")
    func testManualAdjustmentOverridesIncompleteTransactions() async throws {
        let modelContext = try createTestModelContext()

        let credit = Credit(
            name: "Кредит",
            amount: 100_000.0,
            interestRate: 0.0,
            monthlyPayment: 1_000.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.initialRemainingAmount = 100_000.0
        credit.hasInitialRemainingAmount = true
        credit.remainingAmount = 40_000.0
        credit.remainingAmountAdjustment = -60_000.0
        credit.updatedAt = Date()
        modelContext.insert(credit)

        // Имитируем только одну транзакцию (неполная история)
        let transaction = CashflowTransaction(
            transactionType: .creditDebtAdjustment,
            amount: 10_000.0,
            currency: "RUB",
            transactionDate: credit.updatedAt,
            creditID: credit.creditUniqueID,
            note: "Корректировка"
        )
        modelContext.insert(transaction)

        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let endAmount = await dynamicsViewModel.calculateCreditRemainingAmount(
            credit: credit,
            at: Date(),
            accountCurrency: "RUB"
        )

        #expect(abs(endAmount - 40_000.0) < 0.01)
    }

    @Test("Архивные счета скрываются при выключенном фильтре")
    func testArchivedAccountsHiddenWhenFilterOff() async throws {
        let modelContext = try createTestModelContext()

        let activeCard = Card(name: "Активная", cardNumber: "0000", bank: .other, cardType: .debit, currency: "RUB")
        let archivedCard = Card(name: "Архивная", cardNumber: "9999", bank: .other, cardType: .debit, currency: "RUB")
        archivedCard.archivedAt = Date()

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        let activeAccount = FinanceAccount(accountType: .card, accountID: activeCard.cardUniqueID)
        let archivedAccount = FinanceAccount(accountType: .card, accountID: archivedCard.cardUniqueID)
        activeAccount.group = group
        archivedAccount.group = group
        group.accounts = [activeAccount, archivedAccount]

        modelContext.insert(activeCard)
        modelContext.insert(archivedCard)
        modelContext.insert(group)
        modelContext.insert(activeAccount)
        modelContext.insert(archivedAccount)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        #expect(dynamicsViewModel.getAccountsForCalculation().count == 1)

        dynamicsViewModel.handle(.setShowArchivedAccounts(true))
        let allAccounts = dynamicsViewModel.getAccountsForCalculation()
        #expect(allAccounts.count == 2)
    }
}
