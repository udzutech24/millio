//
//  CreditManagerTests.swift
//  millioTests
//
//  Created by Claude on 01.02.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct CreditManagerTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([Credit.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(Credit.self)
        try context.save()
        return context
    }

    @Test("getAllCredits фильтрует архивные")
    func testGetAllCreditsFiltersArchived() throws {
        let context = try createTestModelContext()

        let active = Credit(
            name: "Активный",
            amount: 100000,
            interestRate: 15,
            monthlyPayment: 5000,
            startDate: Date(),
            termMonths: 24,
            currency: "RUB",
            bank: .sberbank,
            creditType: .consumer
        )

        let archived = Credit(
            name: "Архивный",
            amount: 50000,
            interestRate: 10,
            monthlyPayment: 3000,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .tinkoff,
            creditType: .consumer
        )
        archived.archivedAt = Date()

        context.insert(active)
        context.insert(archived)
        try context.save()

        CreditManager.shared.setup(modelContext: context)
        let credits = CreditManager.shared.getAllCredits()

        #expect(credits.count == 1)
        #expect(credits.first?.name == "Активный")
    }

    @Test("getFavoriteCredits возвращает только избранные")
    func testGetFavoriteCredits() throws {
        let context = try createTestModelContext()

        let normal = Credit(
            name: "Обычный",
            amount: 100000,
            interestRate: 15,
            monthlyPayment: 5000,
            startDate: Date(),
            termMonths: 24,
            currency: "RUB",
            bank: .sberbank,
            creditType: .consumer
        )
        normal.isFavorite = false

        let favorite = Credit(
            name: "Избранный",
            amount: 50000,
            interestRate: 10,
            monthlyPayment: 3000,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .tinkoff,
            creditType: .consumer
        )
        favorite.isFavorite = true

        context.insert(normal)
        context.insert(favorite)
        try context.save()

        CreditManager.shared.setup(modelContext: context)
        let favorites = CreditManager.shared.getFavoriteCredits()

        #expect(favorites.count == 1)
        #expect(favorites.first?.name == "Избранный")
    }

    @Test("getCredits(by type) фильтрует по типу кредита")
    func testGetCreditsByType() throws {
        let context = try createTestModelContext()

        let consumer = Credit(
            name: "Потребительский",
            amount: 100000,
            interestRate: 15,
            monthlyPayment: 5000,
            startDate: Date(),
            termMonths: 24,
            currency: "RUB",
            bank: .sberbank,
            creditType: .consumer
        )

        let mortgage = Credit(
            name: "Ипотека",
            amount: 5000000,
            interestRate: 8,
            monthlyPayment: 30000,
            startDate: Date(),
            termMonths: 240,
            currency: "RUB",
            bank: .vtb,
            creditType: .mortgage
        )

        context.insert(consumer)
        context.insert(mortgage)
        try context.save()

        CreditManager.shared.setup(modelContext: context)

        let consumers = CreditManager.shared.getCredits(by: .consumer)
        #expect(consumers.count == 1)
        #expect(consumers.first?.name == "Потребительский")

        let mortgages = CreditManager.shared.getCredits(by: .mortgage)
        #expect(mortgages.count == 1)
        #expect(mortgages.first?.name == "Ипотека")
    }

    @Test("getTotalDebt считает сумму остатков долга")
    func testGetTotalDebt() throws {
        let context = try createTestModelContext()

        let credit1 = Credit(
            name: "Кредит 1",
            amount: 100000,
            interestRate: 15,
            monthlyPayment: 5000,
            startDate: Date(),
            termMonths: 24,
            currency: "RUB",
            bank: .sberbank,
            creditType: .consumer
        )
        credit1.remainingAmount = 80000

        let credit2 = Credit(
            name: "Кредит 2",
            amount: 50000,
            interestRate: 10,
            monthlyPayment: 3000,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .tinkoff,
            creditType: .consumer
        )
        credit2.remainingAmount = 30000

        context.insert(credit1)
        context.insert(credit2)
        try context.save()

        CreditManager.shared.setup(modelContext: context)
        let total = CreditManager.shared.getTotalDebt()

        #expect(abs(total - 110000) < 0.01)
    }

    @Test("getTotalMonthlyPayments считает сумму ежемесячных платежей")
    func testGetTotalMonthlyPayments() throws {
        let context = try createTestModelContext()

        let credit1 = Credit(
            name: "Кредит 1",
            amount: 100000,
            interestRate: 15,
            monthlyPayment: 5000,
            startDate: Date(),
            termMonths: 24,
            currency: "RUB",
            bank: .sberbank,
            creditType: .consumer
        )

        let credit2 = Credit(
            name: "Кредит 2",
            amount: 50000,
            interestRate: 10,
            monthlyPayment: 3000,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .tinkoff,
            creditType: .consumer
        )

        context.insert(credit1)
        context.insert(credit2)
        try context.save()

        CreditManager.shared.setup(modelContext: context)
        let total = CreditManager.shared.getTotalMonthlyPayments()

        #expect(abs(total - 8000) < 0.01)
    }
}
