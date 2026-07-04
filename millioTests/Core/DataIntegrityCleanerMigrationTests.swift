// DataIntegrityCleanerMigrationTests.swift
// millioTests
//
// Тест однократного патча archiveZeroQuantityInvestmentsIfNeeded.
// Проверяет что старые "проданные" позиции (marketQuantity == 0, archivedAt == nil)
// получают archivedAt, и что патч не применяется повторно.

import Testing
import Foundation
import SwiftData
@testable import millio

@MainActor
struct DataIntegrityCleanerMigrationTests {

    // MARK: - Setup

    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Investment.self,
            Card.self,
            Credit.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            AssetCatalogItem.self,
            AssetProviderMapping.self,
            CashflowCustomCategory.self,
            CashflowSystemCategoryOverride.self,
            HistoricalRate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() throws -> ModelContext {
        let ctx = Self.sharedContainer.mainContext
        try ctx.deleteAll(Investment.self)
        try ctx.save()
        return ctx
    }

    private let migrationKey = "migration.archiveZeroQuantityInvestments.v1"

    private func resetMigrationFlag() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
    }

    // MARK: - Tests

    @Test("Позиции с marketQuantity == 0 архивируются однократным патчем")
    func archivesZeroQuantityPositions() throws {
        resetMigrationFlag()
        let ctx = try makeContext()

        // Создаём три позиции: две "проданных" и одну активную
        let soldA = Investment(name: "AAPL", amount: 0)
        soldA.marketQuantity = 0.0
        soldA.archivedAt = nil

        let soldB = Investment(name: "BTC", amount: 0)
        soldB.marketQuantity = nil   // nil тоже считается нулём (аналогично executeInvestmentOrder)
        soldB.archivedAt = nil

        let active = Investment(name: "TSLA", amount: 5000)
        active.marketQuantity = 5.0
        active.archivedAt = nil

        ctx.insert(soldA)
        ctx.insert(soldB)
        ctx.insert(active)
        try ctx.save()

        // Запускаем патч
        try DataIntegrityCleaner.archiveZeroQuantityInvestmentsIfNeeded(modelContext: ctx, scopeIdentifier: "test")

        // Проверяем результат
        let all = try ctx.fetch(FetchDescriptor<Investment>())

        let archivedCount = all.filter { $0.archivedAt != nil }.count
        let activeCount = all.filter { $0.archivedAt == nil }.count

        #expect(archivedCount == 2, "Две проданных позиции должны получить archivedAt")
        #expect(activeCount == 1, "Активная позиция не должна быть затронута")
        #expect(active.archivedAt == nil, "Позиция с количеством 5 остаётся активной")
    }

    @Test("Патч не архивирует уже архивированные позиции повторно")
    func doesNotOverwriteExistingArchivedAt() throws {
        resetMigrationFlag()
        let ctx = try makeContext()

        let alreadyArchived = Investment(name: "AAPL", amount: 0)
        alreadyArchived.marketQuantity = 0.0
        let originalDate = Date(timeIntervalSince1970: 1_000_000)
        alreadyArchived.archivedAt = originalDate

        ctx.insert(alreadyArchived)
        try ctx.save()

        try DataIntegrityCleaner.archiveZeroQuantityInvestmentsIfNeeded(modelContext: ctx, scopeIdentifier: "test")

        // Уже архивированные не попадают в fetch (#Predicate archivedAt == nil)
        // значит дата не должна измениться
        #expect(alreadyArchived.archivedAt == originalDate, "Дата архивирования не перезаписывается")
    }

    @Test("Патч выполняется только один раз — флаг UserDefaults блокирует повторный запуск")
    func idempotency() throws {
        resetMigrationFlag()
        let ctx = try makeContext()

        let sold = Investment(name: "ETH", amount: 0)
        sold.marketQuantity = 0.0
        sold.archivedAt = nil
        ctx.insert(sold)
        try ctx.save()

        // Первый запуск — должен сработать
        try DataIntegrityCleaner.archiveZeroQuantityInvestmentsIfNeeded(modelContext: ctx, scopeIdentifier: "test")
        #expect(sold.archivedAt != nil, "После первого запуска archivedAt выставлен")

        // Сбрасываем archivedAt вручную — симулируем "незапрошенный" повторный запуск
        sold.archivedAt = nil
        try ctx.save()

        // Второй запуск — флаг уже установлен, ничего не должно измениться
        try DataIntegrityCleaner.archiveZeroQuantityInvestmentsIfNeeded(modelContext: ctx, scopeIdentifier: "test")
        #expect(sold.archivedAt == nil, "Повторный запуск заблокирован флагом UserDefaults")
    }

    @Test("Патч не падает на пустом store")
    func emptyStoreDoesNotCrash() throws {
        resetMigrationFlag()
        let ctx = try makeContext()
        // Просто не должен бросить
        try DataIntegrityCleaner.archiveZeroQuantityInvestmentsIfNeeded(modelContext: ctx, scopeIdentifier: "test")
    }
}
