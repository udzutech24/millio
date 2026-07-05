// DataIntegrityCleanerBudgetLimitDedupTests.swift
// millioTests
//
// Тест dedupeBudgetCategoryLimitsOnLaunch. Проверяет, что дубли BudgetCategoryLimit с одинаковым
// (budgetID, categoryRawValue) (та же уязвимость, что была у CashflowCustomCategory/
// CashbackCustomCategory — краш Fatal error: Duplicate values for key в Dictionary(uniqueKeysWithValues:)
// по categoryRawValue в CashflowViewModel+History.swift) схлопываются в одну запись при старте приложения.
//
// Намеренно БЕЗ одноразового UserDefaults-флага (по образцу Cashflow/Cashback-фиксов): холодный старт
// создаёт первый DIContainer на guest-сторе ДО restoreSession/synchronizeDataScope, а реальный
// user-стор открывается вторым DIContainer.create() через rebindDataScope. Общий флаг сгорал бы на
// guest-сторе, и реальный user-стор с дублями никогда бы не дочищался. Патч гоняется на КАЖДОМ create().

import Testing
import Foundation
import SwiftData
@testable import millio

@MainActor
struct DataIntegrityCleanerBudgetLimitDedupTests {

    // MARK: - Setup

    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            BudgetPlan.self,
            BudgetCategoryLimit.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() throws -> ModelContext {
        let ctx = Self.sharedContainer.mainContext
        try ctx.deleteAll(BudgetCategoryLimit.self)
        try ctx.deleteAll(BudgetPlan.self)
        try ctx.save()
        return ctx
    }

    private func makeSeparateContainer() -> ModelContainer {
        let schema = Schema([BudgetPlan.self, BudgetCategoryLimit.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Tests

    @Test("Два BudgetCategoryLimit с одинаковым (budgetID, categoryRawValue) схлопываются в одну запись")
    func dedupesLimitsWithSameBudgetAndCategory() throws {
        let ctx = try makeContext()

        let budgetID = UUID().uuidString
        let older = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: .expense,
            categoryRawValue: "food",
            limitAmount: 1000
        )
        older.updatedAt = Date(timeIntervalSince1970: 1_000)

        let newer = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: .expense,
            categoryRawValue: "food",
            limitAmount: 2000
        )
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)

        ctx.insert(older)
        ctx.insert(newer)
        try ctx.save()

        try DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<BudgetCategoryLimit>())
        #expect(remaining.count == 1, "Должен остаться только один лимит на эту категорию в этом бюджете")
        #expect(remaining.first?.limitAmount == 2000, "Побеждает объект с более поздним updatedAt")
    }

    @Test("Один и тот же categoryRawValue в разных бюджетах (budgetID) — не дубли")
    func sameCategoryRawValueInDifferentBudgetsIsNotDuplicate() throws {
        let ctx = try makeContext()

        let limitInJanuary = BudgetCategoryLimit(
            budgetID: UUID().uuidString,
            categoryKind: .expense,
            categoryRawValue: "food",
            limitAmount: 1000
        )
        let limitInFebruary = BudgetCategoryLimit(
            budgetID: UUID().uuidString,
            categoryKind: .expense,
            categoryRawValue: "food",
            limitAmount: 1500
        )
        ctx.insert(limitInJanuary)
        ctx.insert(limitInFebruary)
        try ctx.save()

        try DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<BudgetCategoryLimit>())
        #expect(remaining.count == 2, "Один и тот же categoryRawValue в разных бюджетных планах — не дубль")
    }

    @Test("Повторные запуски безопасны и продолжают чистить новые дубли")
    func repeatedRunsKeepCleaningNewDuplicates() throws {
        let ctx = try makeContext()

        let budgetID = UUID().uuidString
        let first = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: .expense,
            categoryRawValue: "transport",
            limitAmount: 500
        )
        first.updatedAt = Date(timeIntervalSince1970: 1_000)
        ctx.insert(first)
        try ctx.save()

        // Первый запуск — стор без дублей, безопасен на пустом/чистом сторе
        try DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch(modelContext: ctx)

        // Дубль появился ПОСЛЕ первого запуска (например, CloudKit merge между запусками)
        let duplicate = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: .expense,
            categoryRawValue: "transport",
            limitAmount: 800
        )
        duplicate.updatedAt = Date(timeIntervalSince1970: 2_000)
        ctx.insert(duplicate)
        try ctx.save()

        // Второй запуск — без одноразового флага дубль обязан вычиститься.
        try DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<BudgetCategoryLimit>())
        #expect(remaining.count == 1, "Патч без одноразового флага обязан вычищать дубли на каждом запуске")
        #expect(remaining.first?.limitAmount == 800, "Побеждает объект с более поздним updatedAt")
    }

    @Test("Guest→user: патч на почти пустом guest-сторе не мешает дочистке user-стора с дублями")
    func guestScopeRunDoesNotBlockUserScopeCleanup() throws {
        let guestContainer = makeSeparateContainer()
        let guestContext = guestContainer.mainContext
        // Guest-стор пуст — типичная ситуация холодного старта до логина.
        try DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch(modelContext: guestContext)

        let userContainer = makeSeparateContainer()
        let userContext = userContainer.mainContext

        let budgetID = UUID().uuidString
        let older = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: .expense,
            categoryRawValue: "entertainment",
            limitAmount: 300
        )
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: .expense,
            categoryRawValue: "entertainment",
            limitAmount: 600
        )
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        userContext.insert(older)
        userContext.insert(newer)
        try userContext.save()

        try DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch(modelContext: userContext)

        let remaining = try userContext.fetch(FetchDescriptor<BudgetCategoryLimit>())
        #expect(remaining.count == 1, "User-стор обязан дочиститься независимо от того, что патч уже отработал на guest-сторе")
    }

    @Test("Патч не падает на пустом store")
    func emptyStoreDoesNotCrash() throws {
        let ctx = try makeContext()
        try DataIntegrityCleaner.dedupeBudgetCategoryLimitsOnLaunch(modelContext: ctx)
    }

    @Test("Runtime defense-in-depth: dedupedByCategoryRawValue схлопывает дубли и не падает на них")
    func dedupedByCategoryRawValueCollapsesDuplicates() throws {
        let budgetID = UUID().uuidString
        let older = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: .expense,
            categoryRawValue: "food",
            limitAmount: 1000
        )
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: .expense,
            categoryRawValue: "food",
            limitAmount: 2000
        )
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)

        let deduped = BudgetCategoryLimit.dedupedByCategoryRawValue([older, newer])

        #expect(deduped.count == 1)
        #expect(deduped.first?.limitAmount == 2000, "Побеждает объект с более поздним updatedAt")

        // До фикса это падало бы с Fatal error: Duplicate values for key.
        let dict = Dictionary(uniqueKeysWithValues: deduped.map { ($0.categoryRawValue, $0.limitAmount) })
        #expect(dict["food"] == 2000)
    }
}
