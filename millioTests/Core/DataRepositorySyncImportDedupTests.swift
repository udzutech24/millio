// DataRepositorySyncImportDedupTests.swift
// millioTests
//
// Регресс на "Дыру 2" адверсарной проверки: синхронный DataRepository.importAllData(_:)
// не вызывал DataIntegrityCleaner.dedupeAll (в отличие от importAllDataAsync). Это
// использует legacy→scope миграция первого логина (millioApp.migrateExistingStoresIfNeeded
// → targetRepository.importAllData(payload)) — дубли CashflowCustomCategory из старого
// стора копировались в новый без очистки.

import Testing
import Foundation
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct DataRepositorySyncImportDedupTests {
    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            Item.self,
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            CashflowCustomCategory.self,
            CashflowSystemCategoryOverride.self,
            HistoricalRate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    @Test("Sync importAllData дедуплицирует CashflowCustomCategory с одинаковым categoryID на входе")
    func syncImportAllDataDeduplicatesDuplicateCategories() throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        CashflowFeatureRegistration.register()

        // "Старый" стор (источник legacy→scope миграции) с дублем — тем же сценарием,
        // что вызывал прод-краш: два CashflowCustomCategory с одинаковым categoryID.
        let sourceContainer = makeContainer()
        let sourceContext = sourceContainer.mainContext

        let sharedID = UUID().uuidString
        let older = CashflowCustomCategory(kind: .expense, name: "Такси")
        older.categoryID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = CashflowCustomCategory(kind: .expense, name: "Такси (переименовано)")
        newer.categoryID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        sourceContext.insert(older)
        sourceContext.insert(newer)
        try sourceContext.save()

        let payload = try DataRepository.exportAllData(from: sourceContext)

        // "Новый" (target) стор — пустой, как при первом логине пользователя.
        let targetContainer = makeContainer()
        let targetRepository = DataRepository(modelContext: targetContainer.mainContext, modelContainer: targetContainer)

        // Именно СИНХРОННЫЙ путь — тот же, что использует migrateExistingStoresIfNeeded.
        try targetRepository.importAllData(payload)

        let imported = try targetContainer.mainContext.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(imported.count == 1, "Sync importAllData обязан дедуплицировать дубли categoryID так же, как async-версия")
        #expect(imported.first?.name == "Такси (переименовано)", "Побеждает объект с более поздним updatedAt")
    }

    @Test("Sync importAllData не трогает категории без дублей")
    func syncImportAllDataLeavesDistinctCategoriesIntact() throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        CashflowFeatureRegistration.register()

        let sourceContainer = makeContainer()
        let sourceContext = sourceContainer.mainContext
        sourceContext.insert(CashflowCustomCategory(kind: .expense, name: "A"))
        sourceContext.insert(CashflowCustomCategory(kind: .income, name: "B"))
        try sourceContext.save()

        let payload = try DataRepository.exportAllData(from: sourceContext)

        let targetContainer = makeContainer()
        let targetRepository = DataRepository(modelContext: targetContainer.mainContext, modelContainer: targetContainer)
        try targetRepository.importAllData(payload)

        let imported = try targetContainer.mainContext.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(imported.count == 2, "Категории без дублей должны сохраниться при синхронном импорте")
    }
}
