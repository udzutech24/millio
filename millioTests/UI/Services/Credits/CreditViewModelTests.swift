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
        try context.deleteAll(CashflowTransaction.self)
        try context.deleteAll(Credit.self)
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
            paymentMode: .dayOfMonth,
            paymentDayOfMonth: 15,
            nextPaymentDate: nil,
            reminderEnabled: false,
            reminderDaysBefore: nil,
            reminderTime: nil,
            includeInTotal: credit.includeInTotal,
            uniqueID: nil
        ))

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = (try? modelContext.fetch(descriptor)) ?? []

        #expect(transactions.count == 1)
        #expect(transactions.first?.transactionType == .creditDebtAdjustment)
        #expect(abs((transactions.first?.amount ?? 0) - 200.0) < 0.01)
    }

    @Test("Ручная корректировка остатка долга сохраняется после автопересчета")
    func testManualDebtAdjustmentPersistsAfterAutoRecalc() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CreditViewModel(modelContext: modelContext)

        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .month, value: -2, to: Date()) ?? Date()
        let endDate = calendar.date(byAdding: .month, value: 12, to: startDate) ?? Date()

        let credit = Credit(
            name: "Кредит с корректировкой",
            amount: 1200.0,
            interestRate: 0.0,
            monthlyPayment: 100.0,
            startDate: startDate,
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer,
            endDate: endDate
        )
        credit.remainingAmount = 1200.0
        modelContext.insert(credit)
        try modelContext.save()

        viewModel.handle(.editCredit(credit))
        viewModel.handle(.updateCredit(
            name: credit.name,
            amount: credit.amount,
            monthlyPayment: credit.monthlyPayment,
            endDate: endDate,
            remainingAmount: 850.0,
            currency: credit.currency,
            bank: credit.bank,
            creditType: credit.creditType,
            isFavorite: credit.isFavorite,
            paymentMode: .dayOfMonth,
            paymentDayOfMonth: 10,
            nextPaymentDate: nil,
            reminderEnabled: false,
            reminderDaysBefore: nil,
            reminderTime: nil,
            includeInTotal: credit.includeInTotal,
            uniqueID: nil
        ))

        viewModel.handle(.loadCredits)

        let updated = viewModel.state.credits.first
        #expect(abs((updated?.remainingAmount ?? 0) - 850.0) < 0.01)
        #expect(abs((updated?.remainingAmountAdjustment ?? 0)) > 0.01)
    }

    @Test("Отрицательное значение долга клампится в 0 и корректно пишет adjustment")
    func testNegativeRemainingAmountIsClamped() throws {
        let modelContext = try createTestModelContext()
        _ = CreditViewModel(modelContext: modelContext)

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
        credit.remainingAmount = 500.0
        modelContext.insert(credit)
        try modelContext.save()

        credit.applyManualRemainingAmount(-100.0)

        #expect(credit.remainingAmount == 0.0)
        #expect(credit.remainingAmountAdjustment <= 0.0)
    }

    @Test("paymentMode dayOfMonth сохраняет день и очищает nextDate")
    func testPaymentModeDayOfMonthClearsNextDate() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CreditViewModel(modelContext: modelContext)
        let uniqueID = UUID().uuidString

        viewModel.handle(.updateCredit(
            name: "Кредит A",
            amount: 200_000,
            monthlyPayment: 10_000,
            endDate: Date(),
            remainingAmount: 150_000,
            currency: "RUB",
            bank: .other,
            creditType: .consumer,
            isFavorite: false,
            paymentMode: .dayOfMonth,
            paymentDayOfMonth: 17,
            nextPaymentDate: Date().addingTimeInterval(86_400),
            reminderEnabled: false,
            reminderDaysBefore: nil,
            reminderTime: nil,
            includeInTotal: true,
            uniqueID: uniqueID
        ))

        guard let created = viewModel.state.credits.first(where: { $0.creditUniqueID == uniqueID }) else {
            Issue.record("Credit not created")
            return
        }

        #expect(created.paymentMode == .dayOfMonth)
        #expect(created.paymentDayOfMonth == 17)
        #expect(created.nextPaymentDate == nil)
    }

    @Test("paymentMode nextDate сохраняет дату и очищает dayOfMonth")
    func testPaymentModeNextDateClearsDayOfMonth() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CreditViewModel(modelContext: modelContext)
        let uniqueID = UUID().uuidString
        let nextDate = Date().addingTimeInterval(172_800)

        viewModel.handle(.updateCredit(
            name: "Кредит B",
            amount: 300_000,
            monthlyPayment: 20_000,
            endDate: Date(),
            remainingAmount: 250_000,
            currency: "RUB",
            bank: .other,
            creditType: .consumer,
            isFavorite: false,
            paymentMode: .nextDate,
            paymentDayOfMonth: 25,
            nextPaymentDate: nextDate,
            reminderEnabled: false,
            reminderDaysBefore: nil,
            reminderTime: nil,
            includeInTotal: true,
            uniqueID: uniqueID
        ))

        guard let created = viewModel.state.credits.first(where: { $0.creditUniqueID == uniqueID }) else {
            Issue.record("Credit not created")
            return
        }

        #expect(created.paymentMode == .nextDate)
        #expect(created.paymentDayOfMonth == nil)
        #expect(created.nextPaymentDate != nil)
    }

    @Test("Напоминание при disable очищает связанные поля")
    func testReminderDisableClearsFields() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CreditViewModel(modelContext: modelContext)
        let uniqueID = UUID().uuidString
        let reminderTime = Date()

        viewModel.handle(.updateCredit(
            name: "Кредит C",
            amount: 100_000,
            monthlyPayment: 5_000,
            endDate: Date(),
            remainingAmount: 80_000,
            currency: "RUB",
            bank: .other,
            creditType: .consumer,
            isFavorite: false,
            paymentMode: .dayOfMonth,
            paymentDayOfMonth: 15,
            nextPaymentDate: nil,
            reminderEnabled: true,
            reminderDaysBefore: 3,
            reminderTime: reminderTime,
            includeInTotal: true,
            uniqueID: uniqueID
        ))

        guard let created = viewModel.state.credits.first(where: { $0.creditUniqueID == uniqueID }) else {
            Issue.record("Credit not created")
            return
        }

        #expect(created.reminderEnabled)
        #expect(created.reminderDaysBefore == 3)
        #expect(created.reminderTime != nil)

        viewModel.handle(.editCredit(created))
        viewModel.handle(.updateCredit(
            name: created.name,
            amount: created.amount,
            monthlyPayment: created.monthlyPayment,
            endDate: created.endDate ?? Date(),
            remainingAmount: created.remainingAmount,
            currency: created.currency,
            bank: created.bank,
            creditType: created.creditType,
            isFavorite: created.isFavorite,
            paymentMode: created.paymentMode,
            paymentDayOfMonth: created.paymentDayOfMonth,
            nextPaymentDate: created.nextPaymentDate,
            reminderEnabled: false,
            reminderDaysBefore: 7,
            reminderTime: Date().addingTimeInterval(3_600),
            includeInTotal: true,
            uniqueID: nil
        ))

        guard let updated = viewModel.state.credits.first(where: { $0.creditUniqueID == uniqueID }) else {
            Issue.record("Credit not updated")
            return
        }

        #expect(updated.reminderEnabled == false)
        #expect(updated.reminderDaysBefore == nil)
        #expect(updated.reminderTime == nil)
    }
}
