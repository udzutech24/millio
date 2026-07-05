//
//  CashflowCategoryServiceDedupTests.swift
//  millioTests
//
//  Регрессионный тест на краш `Fatal error: Duplicate values for key: 'custom:<UUID>'`.
//  Воспроизводит сценарий: в сторе оказались два CashflowCustomCategory с одинаковым
//  categoryID (categoryID не был защищён @Attribute(.unique), CloudKit merge/restore
//  мог создать дубль) — ForEach/LazyVGrid по [CashflowCategoryOption] падал, т.к.
//  id == rawValue == "custom:<categoryID>" совпадал у обоих объектов.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowCategoryServiceDedupTests {
    private static let schema = Schema([
        Card.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        CashflowCustomCategory.self,
        CashflowSystemCategoryOverride.self,
        HistoricalRate.self
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func createTestModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func makeService(
        modelContext: ModelContext,
        customCategories: [CashflowCustomCategory]
    ) -> CashflowCategoryService {
        let suiteName = "CashflowCategoryServiceDedupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return CashflowCategoryService(
            modelContext: modelContext,
            categoryPinPrefs: CashflowCategoryPinPrefs(defaults: defaults),
            bulkExpenseMerchantPrefs: CashflowBulkExpenseMerchantCategoryPrefs(defaults: defaults),
            customCategoryVisibilityPrefs: CashflowCustomCategoryVisibilityPrefs(defaults: defaults),
            now: { Date() },
            customCategoriesProvider: { customCategories },
            systemCategoryOverridesProvider: { [] },
            onCategoriesChanged: {}
        )
    }

    // MARK: - dedupedCustomCategories (чистая логика)

    @Test("Дубли categoryID схлопываются в одну запись — побеждает более поздний updatedAt")
    func dedupKeepsLatestUpdatedAt() throws {
        let sharedID = UUID().uuidString

        let older = CashflowCustomCategory(kind: .expense, name: "Такси")
        older.categoryID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1_000)

        let newer = CashflowCustomCategory(kind: .expense, name: "Такси (переименовано)")
        newer.categoryID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)

        let result = CashflowCategoryService.dedupedCustomCategories([older, newer])

        #expect(result.count == 1, "Два объекта с одинаковым categoryID должны схлопнуться в один")
        #expect(result.first?.name == "Такси (переименовано)", "Побеждает объект с более поздним updatedAt")
    }

    @Test("Категории с разными categoryID не затрагиваются")
    func distinctCategoriesUnaffected() throws {
        let a = CashflowCustomCategory(kind: .expense, name: "A")
        let b = CashflowCustomCategory(kind: .expense, name: "B")

        let result = CashflowCategoryService.dedupedCustomCategories([a, b])

        #expect(result.count == 2)
    }

    @Test("Пустой массив не падает")
    func emptyArrayDoesNotCrash() throws {
        let result = CashflowCategoryService.dedupedCustomCategories([])
        #expect(result.isEmpty)
    }

    @Test("Три дубля с одним categoryID схлопываются в один экземпляр")
    func threeWayDuplicateCollapsesToOne() throws {
        let sharedID = UUID().uuidString
        let first = CashflowCustomCategory(kind: .expense, name: "V1")
        first.categoryID = sharedID
        first.updatedAt = Date(timeIntervalSince1970: 1_000)

        let second = CashflowCustomCategory(kind: .expense, name: "V2")
        second.categoryID = sharedID
        second.updatedAt = Date(timeIntervalSince1970: 3_000)

        let third = CashflowCustomCategory(kind: .expense, name: "V3")
        third.categoryID = sharedID
        third.updatedAt = Date(timeIntervalSince1970: 2_000)

        let result = CashflowCategoryService.dedupedCustomCategories([first, second, third])

        #expect(result.count == 1)
        #expect(result.first?.name == "V2", "Побеждает объект с максимальным updatedAt среди всех дублей")
    }

    // MARK: - categoryOptions(for:) — сквозной регресс сценария из краша

    @Test("categoryOptions возвращает уникальные id при дубле categoryID в сторе — краш не воспроизводится")
    func categoryOptionsProducesUniqueIDsDespiteDuplicateStore() throws {
        let modelContext = try createTestModelContext()

        let sharedID = UUID().uuidString
        let first = CashflowCustomCategory(kind: .expense, name: "Такси")
        first.categoryID = sharedID
        first.updatedAt = Date(timeIntervalSince1970: 1_000)

        let duplicate = CashflowCustomCategory(kind: .expense, name: "Такси (дубль)")
        duplicate.categoryID = sharedID
        duplicate.updatedAt = Date(timeIntervalSince1970: 2_000)

        let service = makeService(modelContext: modelContext, customCategories: [first, duplicate])
        let options = service.categoryOptions(for: .expense)

        let customOptions = options.filter(\.isCustom)
        #expect(customOptions.count == 1, "Дубли с одинаковым categoryID должны схлопнуться в одну опцию")

        let ids = Set(options.map(\.id))
        #expect(ids.count == options.count, "id всех CashflowCategoryOption обязаны быть уникальны — иначе ForEach/LazyVGrid падает с Fatal error: Duplicate values for key")
    }
}
