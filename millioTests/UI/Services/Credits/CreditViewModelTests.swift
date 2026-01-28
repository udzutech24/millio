//
//  CreditViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 28.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct CreditViewModelTests {

    /// Общий контейнер для всех тестов (SwiftData нестабилен при создании множества контейнеров)
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Credit.self,
            CashflowTransaction.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    /// Получить чистый контекст (очищаем данные от предыдущих тестов)
    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.delete(model: CashflowTransaction.self)
        try context.delete(model: Credit.self)
        try context.save()
        return context
    }

    @Test("Редактирование остатка долга кредита создает транзакцию корректировки")
    func testEditCreditCreatesDebtAdjustmentTransaction() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CreditViewModel(modelContext: modelContext)

        let credit = Credit(
            name: "Кредит",
            amount: 1000.0,
            interestRate: 0.0,
            monthlyPayment: 100.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.remainingAmount = 1000.0
        modelContext.insert(credit)
        try modelContext.save()

        viewModel.handle(.editCredit(credit))
        viewModel.handle(.updateCredit(
            name: credit.name,
            amount: credit.amount,
            monthlyPayment: credit.monthlyPayment,
            endDate: credit.endDate ?? Date(),
            remainingAmount: 800.0,
            currency: credit.currency,
            bank: credit.bank,
            creditType: credit.creditType,
            isFavorite: credit.isFavorite,
            includeInTotal: credit.includeInTotal
        ))

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = (try? modelContext.fetch(descriptor)) ?? []

        #expect(transactions.count == 1)
        #expect(transactions.first?.transactionType == .creditDebtAdjustment)
        #expect(abs((transactions.first?.amount ?? 0) - 200.0) < 0.01)
    }
}
